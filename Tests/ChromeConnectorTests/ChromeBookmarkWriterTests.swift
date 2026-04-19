@testable import BookmarkModel
@testable import ChromeConnector
import Foundation
import Testing

@Suite("ChromeBookmarkWriter")
struct ChromeBookmarkWriterTests {
    private func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    }

    private func temporaryFileURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
    }

    private func makeWorkingCopy(of fixtureName: String) throws -> URL {
        let source = fixtureURL(fixtureName)
        let destination = temporaryFileURL(named: "Bookmarks")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    @Test func writesItemsToChromeRootsAndPreservesMobileRoot() throws {
        let workingFile = try makeWorkingCopy(of: "chrome-bookmarks-simple")
        let writer = ChromeBookmarkWriter(clientID: "chrome-mac-001")

        let barRoot = BookmarkItem(
            id: "root-bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar",
            identifierMap: ["chrome-mac-001": "0bc5d13f-2cba-5d74-951f-3f233fe6c908"]
        )
        let otherRoot = BookmarkItem(
            id: "root-other",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Other Bookmarks",
            identifierMap: ["chrome-mac-001": "82b081ec-3dd3-529c-8475-ab6c344590dd"]
        )
        let exported = BookmarkItem(
            id: "canon-bookmark-1",
            type: .bookmark,
            parentID: "root-bar",
            position: 0,
            title: "Exported Example",
            url: "https://exported.example.com/",
            identifierMap: ["chrome-mac-001": "writer-guid-0001"]
        )

        try writer.write(items: [barRoot, otherRoot, exported], to: workingFile)

        let data = try Data(contentsOf: workingFile)
        let output = try JSONDecoder().decode(ChromeBookmarksFile.self, from: data)

        #expect(output.roots.bookmarkBar.children?.count == 1)
        #expect(output.roots.bookmarkBar.children?.first?.name == "Exported Example")
        #expect(output.roots.bookmarkBar.children?.first?.guid == "writer-guid-0001")
        #expect(output.roots.other.children?.isEmpty == true)

        // Mobile Bookmarks are excluded from sync and must remain untouched.
        #expect(output.roots.synced.children?.count == 1)
        #expect(output.roots.synced.children?.first?.name == "Mobile Bookmark")
    }

    @Test func nestedChildrenAreWrittenInPositionOrder() throws {
        let workingFile = try makeWorkingCopy(of: "chrome-bookmarks-empty")
        let writer = ChromeBookmarkWriter(clientID: "chrome-mac-001")

        let barRoot = BookmarkItem(
            id: "bar-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "bookmarks_bar"
        )
        let otherRoot = BookmarkItem(
            id: "other-root",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "other_bookmarks"
        )
        let folder = BookmarkItem(
            id: "folder-1",
            type: .folder,
            parentID: "bar-root",
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

        try writer.write(items: [barRoot, otherRoot, folder, bookmarkA, bookmarkB], to: workingFile)

        let data = try Data(contentsOf: workingFile)
        let output = try JSONDecoder().decode(ChromeBookmarksFile.self, from: data)
        let folderNode = try #require(output.roots.bookmarkBar.children?.first)
        let childNames = try #require(folderNode.children).map(\.name)
        #expect(childNames == ["A", "B"])
    }

    @Test func missingHardFoldersThrows() throws {
        let workingFile = try makeWorkingCopy(of: "chrome-bookmarks-empty")
        let writer = ChromeBookmarkWriter(clientID: "chrome-mac-001")

        let onlyRoot = BookmarkItem(
            id: "root-bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )

        #expect(throws: ChromeBookmarkWriterError.missingHardFolder("other_bookmarks")) {
            try writer.write(items: [onlyRoot], to: workingFile)
        }
    }

    @Test func rootGUIDMappingWorksWithLocalizedRootTitles() throws {
        let workingFile = try makeWorkingCopy(of: "chrome-bookmarks-empty")
        let writer = ChromeBookmarkWriter(clientID: "chrome-mac-001")

        let barRoot = BookmarkItem(
            id: "canonical-root-bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Barre de favoris",
            identifierMap: ["chrome-mac-001": "0bc5d13f-2cba-5d74-951f-3f233fe6c908"]
        )
        let otherRoot = BookmarkItem(
            id: "canonical-root-other",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Autres favoris",
            identifierMap: ["chrome-mac-001": "82b081ec-3dd3-529c-8475-ab6c344590dd"]
        )
        let localizedBookmark = BookmarkItem(
            id: "canon-bookmark-localized",
            type: .bookmark,
            parentID: "canonical-root-other",
            position: 0,
            title: "Exemple",
            url: "https://exemple.fr/"
        )

        try writer.write(items: [barRoot, otherRoot, localizedBookmark], to: workingFile)

        let data = try Data(contentsOf: workingFile)
        let output = try JSONDecoder().decode(ChromeBookmarksFile.self, from: data)
        #expect(output.roots.bookmarkBar.children?.isEmpty == true)
        #expect(output.roots.other.children?.count == 1)
        #expect(output.roots.other.children?.first?.name == "Exemple")
    }
}
