@testable import BookmarkModel
import Foundation
@testable import MergeEngine
import Testing

@Suite("MergeEngine")
struct MergeEngineTests {
    private let engine = MergeEngine()

    @Test func identifierMatchUpdatesExistingCanonicalItem() {
        let existing = BookmarkItem(
            id: "canonical-1",
            type: .bookmark,
            parentID: "bookmarks_bar",
            position: 0,
            title: "Old",
            url: "https://example.com/",
            dateAdded: Date(timeIntervalSince1970: 1_700_000_000),
            dateModified: Date(timeIntervalSince1970: 1_700_000_100),
            identifierMap: ["chrome-mac-001": "guid-123"]
        )

        let local = BookmarkItem(
            id: "guid-123",
            type: .bookmark,
            parentID: "bar-root",
            position: 2,
            title: "New Title",
            url: "https://Example.com/?utm_source=ads",
            dateAdded: Date(timeIntervalSince1970: 1_700_000_000),
            dateModified: Date(timeIntervalSince1970: 1_700_000_900)
        )

        let barRoot = BookmarkItem(
            id: "bar-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )

        let result = engine.merge(
            canonicalItems: [existing],
            localItems: [barRoot, local],
            clientID: "chrome-mac-001",
            mode: .steadyState
        )

        #expect(result.stats.matchedCount == 1)
        let merged = result.mergedItems.first(where: { $0.id == "canonical-1" })
        #expect(merged?.title == "New Title")
        #expect(merged?.url == "https://example.com/")
        #expect(merged?.identifierMap["chrome-mac-001"] == "guid-123")
    }

    @Test func urlFallbackMatchesWhenIdentifierMissing() {
        let canonicalParent = BookmarkItem(
            id: "bookmarks_bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )
        let canonicalItem = BookmarkItem(
            id: "canonical-1",
            type: .bookmark,
            parentID: "bookmarks_bar",
            position: 0,
            title: "Example",
            url: "https://example.com/path",
            identifierMap: [:]
        )

        let localParent = BookmarkItem(
            id: "chrome-bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )
        let localItem = BookmarkItem(
            id: "guid-local",
            type: .bookmark,
            parentID: "chrome-bar",
            position: 0,
            title: "Example",
            url: "http://EXAMPLE.com/path/"
        )

        let result = engine.merge(
            canonicalItems: [canonicalParent, canonicalItem],
            localItems: [localParent, localItem],
            clientID: "chrome-mac-001",
            mode: .bootstrap
        )

        #expect(result.stats.matchedCount == 2)
        let mergedItem = result.mergedItems.first(where: { $0.id == "canonical-1" })
        #expect(mergedItem?.identifierMap["chrome-mac-001"] == "guid-local")
    }

    @Test func addsUnmatchedItemWithStorageNormalizedURL() {
        let localRoot = BookmarkItem(
            id: "root-1",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )
        let localItem = BookmarkItem(
            id: "local-1",
            type: .bookmark,
            parentID: "root-1",
            position: 0,
            title: "Track",
            url: "https://example.com/path/?utm_source=ad&x=1"
        )

        let result = engine.merge(
            canonicalItems: [],
            localItems: [localRoot, localItem],
            clientID: "chrome-mac-001",
            mode: .bootstrap
        )

        #expect(result.stats.addedCount == 2)
        let added = result.mergedItems.first(where: { $0.title == "Track" })
        #expect(added?.url == "https://example.com/path?x=1")
        #expect(added?.identifierMap["chrome-mac-001"] == "local-1")
    }

    @Test func steadyStateMarksUnmatchedLocalBookmarksForDeletion() {
        let canonicalRoot = BookmarkItem(
            id: "bookmarks_bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar",
            identifierMap: ["chrome-mac-001": "chrome-root"]
        )
        let canonicalItem = BookmarkItem(
            id: "canonical-1",
            type: .bookmark,
            parentID: "bookmarks_bar",
            position: 0,
            title: "Keep",
            url: "https://example.com",
            identifierMap: ["chrome-mac-001": "guid-keep"]
        )

        let localRoot = BookmarkItem(
            id: "chrome-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )
        let localKeep = BookmarkItem(
            id: "guid-keep",
            type: .bookmark,
            parentID: "chrome-root",
            position: 0,
            title: "Keep",
            url: "https://example.com"
        )
        let localExtra = BookmarkItem(
            id: "guid-delete",
            type: .bookmark,
            parentID: "chrome-root",
            position: 1,
            title: "Delete",
            url: "https://delete-me.example.com"
        )

        let result = engine.deletionCandidatesForExport(
            canonicalItems: [canonicalRoot, canonicalItem],
            targetItems: [localRoot, localKeep, localExtra],
            clientID: "chrome-mac-001"
        )

        #expect(result == ["guid-delete"])
    }

    @Test func bootstrapDoesNotReturnDeletionCandidates() {
        let localRoot = BookmarkItem(
            id: "root-1",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )
        let localExtra = BookmarkItem(
            id: "guid-extra",
            type: .bookmark,
            parentID: "root-1",
            position: 0,
            title: "Only Local",
            url: "https://example.com"
        )

        let result = engine.merge(
            canonicalItems: [],
            localItems: [localRoot, localExtra],
            clientID: "chrome-mac-001",
            mode: .bootstrap
        )

        #expect(result.localDeletionCandidateIDs.isEmpty)
    }

    @Test func urlFallbackPrefersParentContextThenTitle() {
        let data = duplicateURLContextFixture()

        let result = engine.merge(
            canonicalItems: data.canonicalItems,
            localItems: data.localItems,
            clientID: "chrome-mac-001",
            mode: .bootstrap
        )

        let matchedB = result.mergedItems.first(where: { $0.id == "canonical-b" })
        #expect(matchedB?.identifierMap["chrome-mac-001"] == "local-id")
        let matchedA = result.mergedItems.first(where: { $0.id == "canonical-a" })
        #expect(matchedA?.identifierMap["chrome-mac-001"] == nil)
    }

    private func duplicateURLContextFixture() -> (canonicalItems: [BookmarkItem], localItems: [BookmarkItem]) {
        (
            canonicalItems: duplicateURLCanonicalItems(),
            localItems: duplicateURLLocalItems()
        )
    }

    private func duplicateURLCanonicalItems() -> [BookmarkItem] {
        let bar = BookmarkItem(
            id: "bookmarks_bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )
        let folderA = BookmarkItem(
            id: "folder-a",
            type: .folder,
            parentID: "bookmarks_bar",
            position: 0,
            title: "A"
        )
        let folderB = BookmarkItem(
            id: "folder-b",
            type: .folder,
            parentID: "bookmarks_bar",
            position: 1,
            title: "B"
        )
        let canonicalA = BookmarkItem(
            id: "canonical-a",
            type: .bookmark,
            parentID: "folder-a",
            position: 0,
            title: "Same URL",
            url: "https://example.com/item"
        )
        let canonicalB = BookmarkItem(
            id: "canonical-b",
            type: .bookmark,
            parentID: "folder-b",
            position: 0,
            title: "Other title",
            url: "https://example.com/item"
        )
        return [bar, folderA, folderB, canonicalA, canonicalB]
    }

    private func duplicateURLLocalItems() -> [BookmarkItem] {
        let localBar = BookmarkItem(
            id: "local-bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )
        let localFolderB = BookmarkItem(
            id: "local-folder-b",
            type: .folder,
            parentID: "local-bar",
            position: 0,
            title: "B"
        )
        let localBookmark = BookmarkItem(
            id: "local-id",
            type: .bookmark,
            parentID: "local-folder-b",
            position: 0,
            title: "Other title",
            url: "http://example.com/item/"
        )
        return [localBar, localFolderB, localBookmark]
    }
}
