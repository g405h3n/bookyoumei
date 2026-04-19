@testable import BookmarkModel
import Foundation
@testable import SafariConnector
import Testing

@Suite("SafariBookmarkWriter")
struct SafariBookmarkWriterTests {
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

    private func isExcludedTopLevelNode(_ node: [String: Any]) -> Bool {
        let title = nodeTitle(node).lowercased()
        return title == "reading list" || title == "com.apple.readinglist" || title == "bookmarks menu"
    }

    @Test func writesItemsAndPreservesExcludedTopLevelSections() throws {
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
        let newFavorite = BookmarkItem(
            id: "fav-item-1",
            type: .bookmark,
            parentID: "canonical-fav-root",
            position: 0,
            title: "Exported Favorite",
            url: "https://fav-export.example.com/"
        )
        let newOther = BookmarkItem(
            id: "other-item-1",
            type: .bookmark,
            parentID: "canonical-other-root",
            position: 0,
            title: "Exported Other",
            url: "https://other-export.example.com/"
        )

        try writer.write(items: [favoritesRoot, otherRoot, newFavorite, newOther], to: workingFile)

        let topLevel = try readTopLevelChildren(from: workingFile)
        let favorites = try #require(topLevel.first(where: isFavoritesRoot))
        let favoriteChildren = try #require(favorites["Children"] as? [[String: Any]])
        #expect(favoriteChildren.count == 1)
        #expect(nodeTitle(favoriteChildren[0]) == "Exported Favorite")
        #expect(favoriteChildren[0]["URLString"] as? String == "https://fav-export.example.com/")

        let exportedOther = topLevel.first(where: { nodeTitle($0) == "Exported Other" })
        #expect(exportedOther?["URLString"] as? String == "https://other-export.example.com/")

        let readingList = try #require(topLevel.first(where: { nodeTitle($0) == "Reading List" }))
        let readingListChildren = try #require(readingList["Children"] as? [[String: Any]])
        #expect(nodeTitle(readingListChildren[0]) == "Should Ignore Reading List Item")

        let bookmarksMenu = try #require(topLevel.first(where: { nodeTitle($0) == "Bookmarks Menu" }))
        let menuChildren = try #require(bookmarksMenu["Children"] as? [[String: Any]])
        #expect(nodeTitle(menuChildren[0]) == "Should Ignore Menu Item")
    }

    @Test func nestedChildrenAreWrittenInPositionOrder() throws {
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
        let folder = BookmarkItem(
            id: "folder-1",
            type: .folder,
            parentID: "fav-root",
            position: 1,
            title: "Folder"
        )
        let bookmarkA = BookmarkItem(
            id: "bookmark-a",
            type: .bookmark,
            parentID: "folder-1",
            position: 1,
            title: "B",
            url: "https://b.example.com/"
        )
        let bookmarkB = BookmarkItem(
            id: "bookmark-b",
            type: .bookmark,
            parentID: "folder-1",
            position: 0,
            title: "A",
            url: "https://a.example.com/"
        )

        try writer.write(items: [favoritesRoot, otherRoot, folder, bookmarkA, bookmarkB], to: workingFile)

        let topLevel = try readTopLevelChildren(from: workingFile)
        let favorites = try #require(topLevel.first(where: isFavoritesRoot))
        let favoritesChildren = try #require(favorites["Children"] as? [[String: Any]])
        let folderNode = try #require(favoritesChildren.first(where: { nodeTitle($0) == "Folder" }))
        let folderChildren = try #require(folderNode["Children"] as? [[String: Any]])
        let childTitles = folderChildren.map(nodeTitle)
        #expect(childTitles == ["A", "B"])
    }

    @Test func missingHardFoldersThrows() throws {
        let workingFile = try makeWorkingCopy(of: "safari-bookmarks-empty")
        let writer = SafariBookmarkWriter(clientID: "safari-mac-001")

        let onlyRoot = BookmarkItem(
            id: "root-favorites",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Favorites Bar"
        )

        #expect(throws: SafariBookmarkWriterError.missingHardFolder("other_bookmarks")) {
            try writer.write(items: [onlyRoot], to: workingFile)
        }
    }

    @Test func identifierMapUUIDIsUsedWhenAvailable() throws {
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
        let mappedBookmark = BookmarkItem(
            id: "bookmark-1",
            type: .bookmark,
            parentID: "fav-root",
            position: 0,
            title: "Mapped UUID",
            url: "https://mapped.example.com/",
            identifierMap: ["safari-mac-001": "mapped-uuid-0001"]
        )

        try writer.write(items: [favoritesRoot, otherRoot, mappedBookmark], to: workingFile)

        let topLevel = try readTopLevelChildren(from: workingFile)
        let favorites = try #require(topLevel.first(where: isFavoritesRoot))
        let favoritesChildren = try #require(favorites["Children"] as? [[String: Any]])
        let written = try #require(favoritesChildren.first(where: { nodeTitle($0) == "Mapped UUID" }))
        #expect(written["WebBookmarkUUID"] as? String == "mapped-uuid-0001")
    }

    @Test func writerLeavesOnlyManagedAndExcludedTopLevelNodes() throws {
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
        let newOther = BookmarkItem(
            id: "other-item-1",
            type: .bookmark,
            parentID: "canonical-other-root",
            position: 0,
            title: "Only Exported Other",
            url: "https://only-exported.example.com/"
        )

        try writer.write(items: [favoritesRoot, otherRoot, newOther], to: workingFile)

        let topLevel = try readTopLevelChildren(from: workingFile)
        #expect(topLevel.contains(where: isFavoritesRoot))
        #expect(topLevel.contains(where: isExcludedTopLevelNode))
        #expect(topLevel.contains(where: { nodeTitle($0) == "Only Exported Other" }))
        #expect(topLevel.contains(where: { nodeTitle($0) == "Root Link" }) == false)
    }
}
