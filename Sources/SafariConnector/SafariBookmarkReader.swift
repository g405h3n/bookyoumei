import BookmarkModel
import Foundation

public struct SafariBookmarkReader: Sendable {
    public let clientID: String?

    public init(clientID: String? = nil) {
        self.clientID = clientID
    }

    public func read(from fileURL: URL) throws -> [BookmarkItem] {
        let data = try Data(contentsOf: fileURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        guard let root = plist as? [String: Any] else {
            throw SafariBookmarkReaderError.invalidFormat
        }

        let topLevelChildren = childNodes(from: root)
        let favoritesNode = topLevelChildren.first(where: isFavoritesRoot)
        let favoritesChildren = favoritesNode.map(childNodes(from:)) ?? []
        let otherChildren = topLevelChildren.filter { node in
            !isFavoritesRoot(node) && !isExcludedTopLevelNode(node)
        }

        var items: [BookmarkItem] = []

        let favoritesRootID = nodeUUID(favoritesNode) ?? "safari-favorites-bar"
        items.append(
            BookmarkItem(
                id: favoritesRootID,
                type: .folder,
                parentID: nil,
                position: 0,
                title: nodeTitle(favoritesNode) ?? "Favorites Bar",
                identifierMap: makeIdentifierMap(uuid: nodeUUID(favoritesNode))
            )
        )
        flattenChildren(of: favoritesChildren, parentID: favoritesRootID, into: &items)

        let otherRootID = "safari-other-bookmarks"
        items.append(
            BookmarkItem(
                id: otherRootID,
                type: .folder,
                parentID: nil,
                position: 0,
                title: "Other Bookmarks"
            )
        )
        flattenChildren(of: otherChildren, parentID: otherRootID, into: &items)

        return items
    }

    public static func defaultBookmarksURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari")
            .appendingPathComponent("Bookmarks.plist")
    }

    // MARK: - Private

    private func flattenChildren(of nodes: [[String: Any]], parentID: String, into items: inout [BookmarkItem]) {
        for (index, node) in nodes.enumerated() {
            let isFolderNode = isFolder(node)
            let itemID = nodeUUID(node) ?? fallbackID(parentID: parentID, index: index, title: nodeTitle(node))
            let itemType: BookmarkItemType = isFolderNode ? .folder : .bookmark

            let item = BookmarkItem(
                id: itemID,
                type: itemType,
                parentID: parentID,
                position: index,
                title: nodeTitle(node) ?? "",
                url: isFolderNode ? nil : nodeURL(node),
                dateAdded: nodeDate(node, key: "DateAdded"),
                dateModified: nodeDate(node, key: "DateModified"),
                identifierMap: makeIdentifierMap(uuid: nodeUUID(node))
            )
            items.append(item)

            if isFolderNode {
                flattenChildren(of: childNodes(from: node), parentID: itemID, into: &items)
            }
        }
    }

    private func childNodes(from node: [String: Any]) -> [[String: Any]] {
        (node["Children"] as? [[String: Any]]) ?? []
    }

    private func isFolder(_ node: [String: Any]) -> Bool {
        if (node["WebBookmarkType"] as? String) == "WebBookmarkTypeList" {
            return true
        }
        return node["Children"] != nil
    }

    private func isFavoritesRoot(_ node: [String: Any]) -> Bool {
        let title = nodeTitle(node)?.lowercased() ?? ""
        let titleMatches = title == "favorites bar" || title == "favoritesbar"

        let type = (node["WebBookmarkType"] as? String)?.lowercased() ?? ""
        return titleMatches && type == "webbookmarktypelist"
    }

    private func isExcludedTopLevelNode(_ node: [String: Any]) -> Bool {
        let title = nodeTitle(node)?.lowercased() ?? ""
        if title == "reading list" || title == "com.apple.readinglist" {
            return true
        }
        if title == "bookmarks menu" || title == "bookmarksmenu" {
            return true
        }
        return false
    }

    private func nodeTitle(_ node: [String: Any]?) -> String? {
        guard let node else { return nil }
        if let title = node["Title"] as? String {
            return title
        }
        if let uriDictionary = node["URIDictionary"] as? [String: Any] {
            if let title = uriDictionary["title"] as? String {
                return title
            }
        }
        return nil
    }

    private func nodeURL(_ node: [String: Any]) -> String? {
        node["URLString"] as? String
    }

    private func nodeUUID(_ node: [String: Any]?) -> String? {
        guard let node else { return nil }
        return node["WebBookmarkUUID"] as? String
    }

    private func nodeDate(_ node: [String: Any], key: String) -> Date? {
        node[key] as? Date
    }

    private func fallbackID(parentID: String, index: Int, title: String?) -> String {
        let safeTitle = (title ?? "untitled").replacingOccurrences(of: " ", with: "_")
        return "\(parentID)-\(index)-\(safeTitle)"
    }

    private func makeIdentifierMap(uuid: String?) -> [String: String] {
        guard let clientID, let uuid else { return [:] }
        return [clientID: uuid]
    }
}

public enum SafariBookmarkReaderError: Error {
    case invalidFormat
}
