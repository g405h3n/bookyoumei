import BookmarkModel
import Foundation

public struct ChromeBookmarkReader: Sendable {
    public let clientID: String?

    public init(clientID: String? = nil) {
        self.clientID = clientID
    }

    public func read(from fileURL: URL) throws -> [BookmarkItem] {
        let data = try Data(contentsOf: fileURL)
        let chromeFile = try JSONDecoder().decode(ChromeBookmarksFile.self, from: data)

        var items: [BookmarkItem] = []

        let barID = chromeFile.roots.bookmarkBar.guid
        items.append(makeHardFolder(from: chromeFile.roots.bookmarkBar, canonicalID: barID))
        flattenChildren(of: chromeFile.roots.bookmarkBar, parentID: barID, into: &items)

        let otherID = chromeFile.roots.other.guid
        items.append(makeHardFolder(from: chromeFile.roots.other, canonicalID: otherID))
        flattenChildren(of: chromeFile.roots.other, parentID: otherID, into: &items)

        return items
    }

    public static func defaultBookmarksURL(profile: String = "Default") -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome")
            .appendingPathComponent(profile)
            .appendingPathComponent("Bookmarks")
    }

    // MARK: - Private

    private func makeHardFolder(from node: ChromeNode, canonicalID: String) -> BookmarkItem {
        BookmarkItem(
            id: canonicalID,
            type: .folder,
            parentID: nil,
            position: 0,
            title: node.name,
            dateAdded: chromeTimestamp(node.dateAdded),
            dateModified: chromeTimestamp(node.dateModified),
            identifierMap: makeIdentifierMap(guid: node.guid)
        )
    }

    private func flattenChildren(of node: ChromeNode, parentID: String, into items: inout [BookmarkItem]) {
        guard let children = node.children else { return }

        for (index, child) in children.enumerated() {
            let itemID = child.guid
            let itemType: BookmarkItemType = child.type == "folder" ? .folder : .bookmark

            let item = BookmarkItem(
                id: itemID,
                type: itemType,
                parentID: parentID,
                position: index,
                title: child.name,
                url: itemType == .bookmark ? child.url : nil,
                dateAdded: chromeTimestamp(child.dateAdded),
                dateModified: chromeTimestamp(child.dateModified),
                identifierMap: makeIdentifierMap(guid: child.guid)
            )
            items.append(item)

            if itemType == .folder {
                flattenChildren(of: child, parentID: itemID, into: &items)
            }
        }
    }

    private func makeIdentifierMap(guid: String) -> [String: String] {
        guard let clientID else { return [:] }
        return [clientID: guid]
    }

    private func chromeTimestamp(_ value: String?) -> Date? {
        guard let value, let microseconds = Int64(value), microseconds > 0 else { return nil }
        let unixSeconds = Double(microseconds) / 1_000_000.0 - 11_644_473_600.0
        return Date(timeIntervalSince1970: unixSeconds)
    }
}
