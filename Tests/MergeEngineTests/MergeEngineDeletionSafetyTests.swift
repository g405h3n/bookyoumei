@testable import BookmarkModel
@testable import MergeEngine
import Testing

@Suite("MergeEngineDeletionSafety")
struct MergeEngineDeletionSafetyTests {
    private let engine = MergeEngine()

    @Test func folderFallbackMatchPreventsDeletionWhenIdentifierMissing() {
        let canonicalRoot = BookmarkItem(
            id: "bookmarks_bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar",
            identifierMap: ["chrome-mac-001": "chrome-root"]
        )
        let canonicalFolder = BookmarkItem(
            id: "canonical-folder",
            type: .folder,
            parentID: "bookmarks_bar",
            position: 0,
            title: "Engineering"
        )

        let targetRoot = BookmarkItem(
            id: "chrome-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )
        let targetFolder = BookmarkItem(
            id: "target-folder",
            type: .folder,
            parentID: "chrome-root",
            position: 0,
            title: "engineering"
        )

        let result = engine.deletionCandidatesForExport(
            canonicalItems: [canonicalRoot, canonicalFolder],
            targetItems: [targetRoot, targetFolder],
            clientID: "chrome-mac-001"
        )

        #expect(result.isEmpty)
    }

    @Test func excludedSubtreeDescendantsAreNeverDeletionCandidates() {
        let canonicalRoot = BookmarkItem(
            id: "bookmarks_bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar",
            identifierMap: ["chrome-mac-001": "chrome-root"]
        )
        let targetRoot = BookmarkItem(
            id: "chrome-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )
        let mobileRoot = BookmarkItem(
            id: "mobile-root",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Mobile Bookmarks"
        )
        let mobileChild = BookmarkItem(
            id: "mobile-child",
            type: .bookmark,
            parentID: "mobile-root",
            position: 0,
            title: "Phone Link",
            url: "https://m.example.com"
        )

        let result = engine.deletionCandidatesForExport(
            canonicalItems: [canonicalRoot],
            targetItems: [targetRoot, mobileRoot, mobileChild],
            clientID: "chrome-mac-001"
        )

        #expect(result.isEmpty)
    }

    @Test func duplicateURLFallbackSelectionIsDeterministic() {
        let canonicalRoot = BookmarkItem(
            id: "bookmarks_bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar",
            identifierMap: ["chrome-mac-001": "chrome-root"]
        )
        let canonicalBookmark = BookmarkItem(
            id: "canonical-target",
            type: .bookmark,
            parentID: "bookmarks_bar",
            position: 0,
            title: "Canonical Title",
            url: "https://example.com/x"
        )

        let targetRoot = BookmarkItem(
            id: "chrome-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )
        let duplicateZ = BookmarkItem(
            id: "zz-duplicate",
            type: .bookmark,
            parentID: "chrome-root",
            position: 0,
            title: "Different A",
            url: "https://example.com/x"
        )
        let duplicateA = BookmarkItem(
            id: "aa-duplicate",
            type: .bookmark,
            parentID: "chrome-root",
            position: 1,
            title: "Different B",
            url: "https://example.com/x"
        )

        let result = engine.deletionCandidatesForExport(
            canonicalItems: [canonicalRoot, canonicalBookmark],
            targetItems: [targetRoot, duplicateZ, duplicateA],
            clientID: "chrome-mac-001"
        )

        #expect(result == ["zz-duplicate"])
    }
}
