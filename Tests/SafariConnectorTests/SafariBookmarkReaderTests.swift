@testable import BookmarkModel
import Foundation
@testable import SafariConnector
import Testing

@Suite("SafariBookmarkReader")
struct SafariBookmarkReaderTests {
    private func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures")!
    }

    @Test func readsSimpleBookmarks() throws {
        let reader = SafariBookmarkReader()
        let items = try reader.read(from: fixtureURL("safari-bookmarks-simple"))

        // 2 hard-folder roots + 1 favorites bookmark + 1 root-level bookmark = 4
        #expect(items.count == 4)
    }

    @Test func hardFolderMapping() throws {
        let reader = SafariBookmarkReader()
        let items = try reader.read(from: fixtureURL("safari-bookmarks-simple"))

        let favorites = items.first { $0.title == "Favorites Bar" && $0.type == .folder }
        #expect(favorites != nil)
        #expect(favorites?.parentID == nil)

        let other = items.first { $0.title == "Other Bookmarks" && $0.type == .folder }
        #expect(other != nil)
        #expect(other?.parentID == nil)
    }

    @Test func readingListAndBookmarksMenuExcluded() throws {
        let reader = SafariBookmarkReader()
        let items = try reader.read(from: fixtureURL("safari-bookmarks-simple"))

        #expect(items.allSatisfy { $0.title != "Reading List" })
        #expect(items.allSatisfy { $0.title != "Bookmarks Menu" })
        #expect(items.allSatisfy { $0.title != "Should Ignore Reading List Item" })
        #expect(items.allSatisfy { $0.title != "Should Ignore Menu Item" })
    }

    @Test func nestedUserFoldersNamedLikeExcludedRootsArePreserved() throws {
        let reader = SafariBookmarkReader()
        let items = try reader.read(from: fixtureURL("safari-bookmarks-nested-exclusion-regression"))

        let nestedReadingListFolder = items.first { $0.title == "Reading List" && $0.type == .folder }
        let nestedBookmarksMenuFolder = items.first { $0.title == "Bookmarks Menu" && $0.type == .folder }
        let readingListChild = items.first { $0.title == "Reading List Child Link" && $0.type == .bookmark }
        let bookmarksMenuChild = items.first { $0.title == "Bookmarks Menu Child Link" && $0.type == .bookmark }

        #expect(nestedReadingListFolder != nil)
        #expect(nestedBookmarksMenuFolder != nil)
        #expect(readingListChild != nil)
        #expect(bookmarksMenuChild != nil)
    }

    @Test func bookmarkFields() throws {
        let reader = SafariBookmarkReader()
        let items = try reader.read(from: fixtureURL("safari-bookmarks-simple"))

        let example = try #require(items.first { $0.title == "Example" })
        #expect(example.type == .bookmark)
        #expect(example.url == "https://example.com/")
        #expect(example.position == 0)
    }

    @Test func parentIDLinkage() throws {
        let reader = SafariBookmarkReader()
        let items = try reader.read(from: fixtureURL("safari-bookmarks-simple"))

        let favorites = try #require(items.first { $0.title == "Favorites Bar" && $0.type == .folder })
        let example = try #require(items.first { $0.title == "Example" })
        let rootLink = try #require(items.first { $0.title == "Root Link" })
        let other = try #require(items.first { $0.title == "Other Bookmarks" && $0.type == .folder })

        #expect(example.parentID == favorites.id)
        #expect(rootLink.parentID == other.id)
    }

    @Test func nestedFolders() throws {
        let reader = SafariBookmarkReader()
        let items = try reader.read(from: fixtureURL("safari-bookmarks-nested"))

        // 2 hard roots + Outer Folder + Inner Folder + Deep Bookmark + Sibling Bookmark = 6
        #expect(items.count == 6)

        let outer = try #require(items.first { $0.title == "Outer Folder" })
        let inner = try #require(items.first { $0.title == "Inner Folder" })
        let deep = try #require(items.first { $0.title == "Deep Bookmark" })
        let sibling = try #require(items.first { $0.title == "Sibling Bookmark" })
        let favorites = try #require(items.first { $0.title == "Favorites Bar" })

        #expect(outer.parentID == favorites.id)
        #expect(inner.parentID == outer.id)
        #expect(deep.parentID == inner.id)
        #expect(sibling.parentID == outer.id)
    }

    @Test func positionOrdering() throws {
        let reader = SafariBookmarkReader()
        let items = try reader.read(from: fixtureURL("safari-bookmarks-nested"))

        let inner = try #require(items.first { $0.title == "Inner Folder" })
        let sibling = try #require(items.first { $0.title == "Sibling Bookmark" })
        #expect(inner.position == 0)
        #expect(sibling.position == 1)
    }

    @Test func emptyBookmarks() throws {
        let reader = SafariBookmarkReader()
        let items = try reader.read(from: fixtureURL("safari-bookmarks-empty"))

        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.type == .folder })
    }

    @Test func identifierMapContainsSafariUUID() throws {
        let reader = SafariBookmarkReader(clientID: "safari-mac-001")
        let items = try reader.read(from: fixtureURL("safari-bookmarks-simple"))

        let example = try #require(items.first { $0.title == "Example" })
        #expect(example.identifierMap["safari-mac-001"] == "fav-example-uuid")
    }

    @Test func invalidFileThrows() {
        let reader = SafariBookmarkReader()
        let badURL = URL(fileURLWithPath: "/nonexistent/path")
        #expect(throws: (any Error).self) {
            try reader.read(from: badURL)
        }
    }
}
