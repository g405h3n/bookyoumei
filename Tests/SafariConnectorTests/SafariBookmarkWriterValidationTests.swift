@testable import BookmarkModel
import Foundation
@testable import SafariConnector
import Testing

@Suite("SafariBookmarkWriterValidation")
struct SafariBookmarkWriterValidationTests {
    private func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures")!
    }

    private func temporaryFileURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
    }

    private func makeWorkingCopy(of fixtureName: String) throws -> URL {
        let source = fixtureURL(fixtureName)
        let destination = temporaryFileURL(named: "Bookmarks.plist")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func readTopLevelChildren(from plistURL: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let root = try #require(plist as? [String: Any])
        return (root["Children"] as? [[String: Any]]) ?? []
    }

    private func nodeTitle(_ node: [String: Any]) -> String {
        if let title = node["Title"] as? String { return title }
        if let uri = node["URIDictionary"] as? [String: Any], let title = uri["title"] as? String {
            return title
        }
        return ""
    }

    private func isFavoritesRoot(_ node: [String: Any]) -> Bool {
        nodeTitle(node).lowercased() == "favorites bar"
    }

    @Test func duplicateHardRootsThrow() throws {
        let workingFile = try makeWorkingCopy(of: "safari-bookmarks-empty")
        let writer = SafariBookmarkWriter(clientID: "safari-mac-001")

        let favoritesRoot1 = BookmarkItem(
            id: "fav-root-1",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Favorites Bar"
        )
        let favoritesRoot2 = BookmarkItem(
            id: "fav-root-2",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Favorites Bar"
        )
        let otherRoot = BookmarkItem(
            id: "other-root",
            type: .folder,
            parentID: nil,
            position: 2,
            title: "Other Bookmarks"
        )

        #expect(throws: SafariBookmarkWriterError.duplicateHardFolder("bookmarks_bar")) {
            try writer.write(items: [favoritesRoot1, favoritesRoot2, otherRoot], to: workingFile)
        }
    }

    @Test func bookmarkWithoutURLThrows() throws {
        let workingFile = try makeWorkingCopy(of: "safari-bookmarks-empty")
        let writer = SafariBookmarkWriter(clientID: "safari-mac-001")

        let favoritesRoot = BookmarkItem(
            id: "fav-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Favorites Bar"
        )
        let otherRoot = BookmarkItem(
            id: "other-root",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Other Bookmarks"
        )
        let invalid = BookmarkItem(
            id: "bookmark-no-url",
            type: .bookmark,
            parentID: "fav-root",
            position: 0,
            title: "No URL",
            url: nil
        )

        #expect(throws: SafariBookmarkWriterError.missingBookmarkURL(itemID: "bookmark-no-url")) {
            try writer.write(items: [favoritesRoot, otherRoot, invalid], to: workingFile)
        }
    }

    @Test func orphanParentReferenceThrows() throws {
        let workingFile = try makeWorkingCopy(of: "safari-bookmarks-empty")
        let writer = SafariBookmarkWriter(clientID: "safari-mac-001")

        let favoritesRoot = BookmarkItem(
            id: "fav-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Favorites Bar"
        )
        let otherRoot = BookmarkItem(
            id: "other-root",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Other Bookmarks"
        )
        let orphan = BookmarkItem(
            id: "orphan-bookmark",
            type: .bookmark,
            parentID: "missing-parent",
            position: 0,
            title: "Orphan",
            url: "https://orphan.example.com/"
        )

        #expect(throws: SafariBookmarkWriterError.orphanedParentReference(
            itemID: "orphan-bookmark",
            parentID: "missing-parent"
        )) {
            try writer.write(items: [favoritesRoot, otherRoot, orphan], to: workingFile)
        }
    }

    @Test func nonFolderParentReferenceThrows() throws {
        let workingFile = try makeWorkingCopy(of: "safari-bookmarks-empty")
        let writer = SafariBookmarkWriter(clientID: "safari-mac-001")

        let favoritesRoot = BookmarkItem(
            id: "fav-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Favorites Bar"
        )
        let otherRoot = BookmarkItem(
            id: "other-root",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Other Bookmarks"
        )
        let bookmarkParent = BookmarkItem(
            id: "bookmark-parent",
            type: .bookmark,
            parentID: "fav-root",
            position: 0,
            title: "Parent Bookmark",
            url: "https://parent.example.com/"
        )
        let child = BookmarkItem(
            id: "child-under-bookmark",
            type: .bookmark,
            parentID: "bookmark-parent",
            position: 0,
            title: "Child",
            url: "https://child.example.com/"
        )

        #expect(throws: SafariBookmarkWriterError.nonFolderParentReference(
            itemID: "child-under-bookmark",
            parentID: "bookmark-parent"
        )) {
            try writer.write(items: [favoritesRoot, otherRoot, bookmarkParent, child], to: workingFile)
        }
    }

    @Test func reusesExistingUUIDWhenNoIdentifierMappingExists() throws {
        let workingFile = try makeWorkingCopy(of: "safari-bookmarks-simple")
        let writer = SafariBookmarkWriter(clientID: "safari-mac-001")

        let favoritesRoot = BookmarkItem(
            id: "canonical-fav-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Favorites Bar",
            identifierMap: ["safari-mac-001": "fav-root-uuid"]
        )
        let otherRoot = BookmarkItem(
            id: "canonical-other-root",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Other Bookmarks"
        )
        let existingLikeBookmark = BookmarkItem(
            id: "canonical-example",
            type: .bookmark,
            parentID: "canonical-fav-root",
            position: 0,
            title: "Example",
            url: "https://example.com/"
        )

        try writer.write(items: [favoritesRoot, otherRoot, existingLikeBookmark], to: workingFile)

        let topLevel = try readTopLevelChildren(from: workingFile)
        let favorites = try #require(topLevel.first(where: isFavoritesRoot))
        let favoritesChildren = try #require(favorites["Children"] as? [[String: Any]])
        let example = try #require(favoritesChildren.first(where: { nodeTitle($0) == "Example" }))
        #expect(example["WebBookmarkUUID"] as? String == "fav-example-uuid")
    }

    @Test func generatesUUIDForNewNodeWithoutMapping() throws {
        let workingFile = try makeWorkingCopy(of: "safari-bookmarks-empty")
        let writer = SafariBookmarkWriter(clientID: "safari-mac-001")

        let favoritesRoot = BookmarkItem(
            id: "fav-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Favorites Bar"
        )
        let otherRoot = BookmarkItem(
            id: "other-root",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Other Bookmarks"
        )
        let createdBookmark = BookmarkItem(
            id: "new-bookmark",
            type: .bookmark,
            parentID: "fav-root",
            position: 0,
            title: "Generated UUID",
            url: "https://generated.example.com/"
        )

        try writer.write(items: [favoritesRoot, otherRoot, createdBookmark], to: workingFile)

        let topLevel = try readTopLevelChildren(from: workingFile)
        let favorites = try #require(topLevel.first(where: isFavoritesRoot))
        let favoritesChildren = try #require(favorites["Children"] as? [[String: Any]])
        let generated = try #require(favoritesChildren.first(where: { nodeTitle($0) == "Generated UUID" }))
        let uuid = try #require(generated["WebBookmarkUUID"] as? String)
        #expect(uuid.isEmpty == false)
    }
}
