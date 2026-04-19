@testable import BookmarkModel
import Foundation
@testable import SafariConnector
import Testing

// swiftlint:disable trailing_comma function_body_length opening_brace
@Suite("SafariBookmarkWriterRegression")
struct SafariBookmarkWriterRegressionTests {
    private func temporaryFileURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
    }

    private func writePlist(
        _ root: [String: Any],
        format: PropertyListSerialization.PropertyListFormat,
        to url: URL
    ) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: format, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private func readPlist(from url: URL) throws
        -> (root: [String: Any], format: PropertyListSerialization.PropertyListFormat)
    {
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        let root = try #require(plist as? [String: Any])
        return (root, format)
    }

    private func childNodes(from root: [String: Any]) -> [[String: Any]] {
        (root["Children"] as? [[String: Any]]) ?? []
    }

    private func nodeTitle(_ node: [String: Any]) -> String {
        if let title = node["Title"] as? String { return title }
        if let uri = node["URIDictionary"] as? [String: Any], let title = uri["title"] as? String {
            return title
        }
        return ""
    }

    private func nodeUUID(_ node: [String: Any]) -> String? {
        node["WebBookmarkUUID"] as? String
    }

    @Test func localizedSystemRootTitlesArePreservedByUUIDClassification() throws {
        let workingFile = temporaryFileURL(named: "Bookmarks.plist")
        let root: [String: Any] = [
            "Children": [
                [
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": "Barra de favoritos",
                    "WebBookmarkUUID": "fav-root-uuid",
                    "Children": [],
                ],
                [
                    "WebBookmarkType": "WebBookmarkTypeLeaf",
                    "Title": "Legacy Root Link",
                    "URLString": "https://legacy.example.com/",
                    "WebBookmarkUUID": "legacy-root-link-uuid",
                ],
                [
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": "Lista de lectura",
                    "WebBookmarkUUID": "reading-list-uuid",
                    "Children": [
                        [
                            "WebBookmarkType": "WebBookmarkTypeLeaf",
                            "Title": "Preserved Reading Item",
                            "URLString": "https://reading.example.com/",
                            "WebBookmarkUUID": "reading-child-uuid",
                        ],
                    ],
                ],
                [
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": "Menu Favoris",
                    "WebBookmarkUUID": "bookmarks-menu-uuid",
                    "Children": [
                        [
                            "WebBookmarkType": "WebBookmarkTypeLeaf",
                            "Title": "Preserved Menu Item",
                            "URLString": "https://menu.example.com/",
                            "WebBookmarkUUID": "menu-child-uuid",
                        ],
                    ],
                ],
            ],
        ]
        try writePlist(root, format: .binary, to: workingFile)

        let writer = SafariBookmarkWriter(clientID: "safari-mac-001")
        let favoritesRoot = BookmarkItem(
            id: "canon-favorites",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Favorites Bar",
            identifierMap: ["safari-mac-001": "fav-root-uuid"]
        )
        let otherRoot = BookmarkItem(
            id: "canon-other",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Other Bookmarks"
        )
        let exportedFavorite = BookmarkItem(
            id: "fav-item-1",
            type: .bookmark,
            parentID: "canon-favorites",
            position: 0,
            title: "Exported Favorite",
            url: "https://fav.example.com/"
        )
        let exportedOther = BookmarkItem(
            id: "other-item-1",
            type: .bookmark,
            parentID: "canon-other",
            position: 0,
            title: "Exported Other",
            url: "https://other.example.com/"
        )

        try writer.write(items: [favoritesRoot, otherRoot, exportedFavorite, exportedOther], to: workingFile)

        let written = try readPlist(from: workingFile)
        let topLevel = childNodes(from: written.root)

        let favorites = try #require(topLevel.first(where: { nodeUUID($0) == "fav-root-uuid" }))
        #expect(nodeTitle(favorites) == "Barra de favoritos")
        let favoritesChildren = try #require(favorites["Children"] as? [[String: Any]])
        #expect(favoritesChildren.count == 1)
        #expect(nodeTitle(favoritesChildren[0]) == "Exported Favorite")

        let readingList = try #require(topLevel.first(where: { nodeUUID($0) == "reading-list-uuid" }))
        let readingChildren = try #require(readingList["Children"] as? [[String: Any]])
        #expect(nodeTitle(readingChildren[0]) == "Preserved Reading Item")

        let bookmarksMenu = try #require(topLevel.first(where: { nodeUUID($0) == "bookmarks-menu-uuid" }))
        let menuChildren = try #require(bookmarksMenu["Children"] as? [[String: Any]])
        #expect(nodeTitle(menuChildren[0]) == "Preserved Menu Item")

        #expect(topLevel.contains(where: { nodeUUID($0) == "legacy-root-link-uuid" }) == false)
        #expect(topLevel.contains(where: { nodeTitle($0) == "Exported Other" }))
    }

    @Test func preservesPlistFormatAndUnknownTopLevelKeys() throws {
        let workingFile = temporaryFileURL(named: "Bookmarks.plist")
        let root: [String: Any] = [
            "CustomMetadata": "keep-me",
            "Children": [
                [
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": "Favorites Bar",
                    "WebBookmarkUUID": "fav-root-uuid",
                    "Children": [],
                ],
            ],
        ]
        try writePlist(root, format: .xml, to: workingFile)

        let writer = SafariBookmarkWriter(clientID: "safari-mac-001")
        let favoritesRoot = BookmarkItem(
            id: "canon-favorites",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Favorites Bar",
            identifierMap: ["safari-mac-001": "fav-root-uuid"]
        )
        let otherRoot = BookmarkItem(
            id: "canon-other",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Other Bookmarks"
        )

        try writer.write(items: [favoritesRoot, otherRoot], to: workingFile)

        let written = try readPlist(from: workingFile)
        #expect(written.format == .xml)
        #expect(written.root["CustomMetadata"] as? String == "keep-me")
    }
}

// swiftlint:enable trailing_comma function_body_length opening_brace
