@testable import BookmarkModel
@testable import ChromeConnector
import Foundation
import Testing

@Suite("ChromeBookmarkReader")
struct ChromeBookmarkReaderTests {
    private func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    }

    // MARK: - Simple fixture

    @Test func readsSimpleBookmarks() throws {
        let reader = ChromeBookmarkReader()
        let items = try reader.read(from: fixtureURL("chrome-bookmarks-simple"))

        // 2 hard-folder roots + 1 bar bookmark + 1 other bookmark = 4
        #expect(items.count == 4)
    }

    @Test func hardFolderMapping() throws {
        let reader = ChromeBookmarkReader()
        let items = try reader.read(from: fixtureURL("chrome-bookmarks-simple"))

        let barFolder = items.first { $0.title == "Bookmarks Bar" && $0.type == .folder }
        #expect(barFolder != nil)
        #expect(barFolder?.parentID == nil)

        let otherFolder = items.first { $0.title == "Other Bookmarks" && $0.type == .folder }
        #expect(otherFolder != nil)
        #expect(otherFolder?.parentID == nil)
    }

    @Test func mobileBookmarksExcluded() throws {
        let reader = ChromeBookmarkReader()
        let items = try reader.read(from: fixtureURL("chrome-bookmarks-simple"))

        let mobileItems = items.filter { $0.title == "Mobile Bookmark" || $0.title == "Mobile Bookmarks" }
        #expect(mobileItems.isEmpty)
    }

    @Test func bookmarkFields() throws {
        let reader = ChromeBookmarkReader()
        let items = try reader.read(from: fixtureURL("chrome-bookmarks-simple"))

        let example = items.first { $0.title == "Example" }
        #expect(example != nil)
        #expect(example?.type == .bookmark)
        #expect(example?.url == "https://example.com/")
        #expect(example?.dateAdded != nil)
        #expect(example?.position == 0)
    }

    @Test func parentIDLinkage() throws {
        let reader = ChromeBookmarkReader()
        let items = try reader.read(from: fixtureURL("chrome-bookmarks-simple"))

        let barFolder = try #require(items.first { $0.title == "Bookmarks Bar" && $0.type == .folder })
        let example = try #require(items.first { $0.title == "Example" })
        #expect(example.parentID == barFolder.id)
    }

    // MARK: - Nested fixture

    @Test func nestedFolders() throws {
        let reader = ChromeBookmarkReader()
        let items = try reader.read(from: fixtureURL("chrome-bookmarks-nested"))

        // bar root + other root + Outer Folder + Inner Folder + Deep Bookmark + Sibling Bookmark = 6
        #expect(items.count == 6)

        let outer = try #require(items.first { $0.title == "Outer Folder" })
        let inner = try #require(items.first { $0.title == "Inner Folder" })
        let deep = try #require(items.first { $0.title == "Deep Bookmark" })
        let sibling = try #require(items.first { $0.title == "Sibling Bookmark" })

        let barFolder = try #require(items.first { $0.title == "Bookmarks Bar" })
        #expect(outer.parentID == barFolder.id)
        #expect(inner.parentID == outer.id)
        #expect(deep.parentID == inner.id)
        #expect(sibling.parentID == outer.id)
    }

    @Test func positionOrdering() throws {
        let reader = ChromeBookmarkReader()
        let items = try reader.read(from: fixtureURL("chrome-bookmarks-nested"))

        let inner = try #require(items.first { $0.title == "Inner Folder" })
        let sibling = try #require(items.first { $0.title == "Sibling Bookmark" })
        #expect(inner.position == 0)
        #expect(sibling.position == 1)
    }

    // MARK: - Empty fixture

    @Test func emptyBookmarks() throws {
        let reader = ChromeBookmarkReader()
        let items = try reader.read(from: fixtureURL("chrome-bookmarks-empty"))

        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.type == .folder })
    }

    // MARK: - Chrome timestamp conversion

    @Test func chromeTimestampConversion() throws {
        let reader = ChromeBookmarkReader()
        let items = try reader.read(from: fixtureURL("chrome-bookmarks-simple"))

        let example = try #require(items.first { $0.title == "Example" })
        #expect(example.dateAdded != nil)

        let year2020 = try #require(DateComponents(calendar: .init(identifier: .gregorian), year: 2020).date)
        let year2030 = try #require(DateComponents(calendar: .init(identifier: .gregorian), year: 2030).date)
        #expect(try #require(example.dateAdded) > year2020)
        #expect(try #require(example.dateAdded) < year2030)
    }

    // MARK: - Identifier map

    @Test func identifierMapContainsChromeGUID() throws {
        let reader = ChromeBookmarkReader(clientID: "chrome-mac-001")
        let items = try reader.read(from: fixtureURL("chrome-bookmarks-simple"))

        let example = try #require(items.first { $0.title == "Example" })
        #expect(example.identifierMap["chrome-mac-001"] == "dff0fb99-f7f5-40a5-89cd-54326fa4d87c")
    }

    // MARK: - Error handling

    @Test func invalidFileThrows() {
        let reader = ChromeBookmarkReader()
        let badURL = URL(fileURLWithPath: "/nonexistent/path")
        #expect(throws: (any Error).self) {
            try reader.read(from: badURL)
        }
    }
}
