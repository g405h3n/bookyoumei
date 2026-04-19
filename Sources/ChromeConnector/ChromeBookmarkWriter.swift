import BookmarkModel
import Foundation

public enum ChromeBookmarkWriterError: Error, Equatable {
    case missingHardFolder(String)
}

public struct ChromeBookmarkWriter: Sendable {
    public let clientID: String?

    public init(clientID: String? = nil) {
        self.clientID = clientID
    }

    public func write(items: [BookmarkItem], to fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL)
        let existing = try JSONDecoder().decode(ChromeBookmarksFile.self, from: data)

        let barRoot = try requireHardRoot(
            from: items,
            expectedGUID: existing.roots.bookmarkBar.guid,
            aliases: ["bookmarks bar", "bookmarks_bar"],
            key: "bookmarks_bar"
        )
        let otherRoot = try requireHardRoot(
            from: items,
            expectedGUID: existing.roots.other.guid,
            aliases: ["other bookmarks", "other_bookmarks"],
            key: "other_bookmarks"
        )

        let childrenByParent = Dictionary(grouping: items.filter { $0.parentID != nil }, by: \.parentID)
        let existingIndex = ExistingNodeIndex(roots: existing.roots)

        var idAllocator = ChromeNodeIDAllocator(startingAt: existingIndex.maxNumericID + 1)
        let barChildren = buildChildren(parentItemID: barRoot.id, childrenByParent: childrenByParent,
                                        existingIndex: existingIndex, idAllocator: &idAllocator)
        let otherChildren = buildChildren(parentItemID: otherRoot.id, childrenByParent: childrenByParent,
                                          existingIndex: existingIndex, idAllocator: &idAllocator)

        let output = ChromeBookmarksFile(
            checksum: existing.checksum,
            roots: ChromeRoots(
                bookmarkBar: makeRootNode(from: existing.roots.bookmarkBar, children: barChildren),
                other: makeRootNode(from: existing.roots.other, children: otherChildren),
                synced: existing.roots.synced
            ),
            version: existing.version
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(output)
        try encoded.write(to: fileURL, options: .atomic)
    }

    public static func defaultBookmarksURL(profile: String = "Default") -> URL {
        ChromeBookmarkReader.defaultBookmarksURL(profile: profile)
    }

    // MARK: - Private

    private func requireHardRoot(
        from items: [BookmarkItem],
        expectedGUID: String,
        aliases: Set<String>,
        key: String
    ) throws -> BookmarkItem {
        let topLevelFolders = items.filter {
            $0.type == .folder && $0.parentID == nil
        }

        if let clientID {
            let byIdentifierMap = topLevelFolders.filter {
                $0.identifierMap[clientID] == expectedGUID
            }
            if let matched = byIdentifierMap.sorted(by: rootSort).first {
                return matched
            }
        }

        let byCanonicalID = topLevelFolders
            .filter { $0.id == expectedGUID }
            .sorted(by: rootSort)
            .first
        if let byCanonicalID {
            return byCanonicalID
        }

        let byAlias = topLevelFolders.filter {
            aliases.contains($0.title.lowercased())
        }
        if let matched = byAlias.sorted(by: rootSort).first {
            return matched
        }

        throw ChromeBookmarkWriterError.missingHardFolder(key)
    }

    private func rootSort(_ lhs: BookmarkItem, _ rhs: BookmarkItem) -> Bool {
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func makeRootNode(from existing: ChromeNode, children: [ChromeNode]) -> ChromeNode {
        ChromeNode(
            children: children,
            dateAdded: existing.dateAdded,
            dateModified: chromeTimestamp(Date()),
            guid: existing.guid,
            id: existing.id,
            name: existing.name,
            type: existing.type,
            url: nil
        )
    }

    private func buildChildren(
        parentItemID: String,
        childrenByParent: [String?: [BookmarkItem]],
        existingIndex: ExistingNodeIndex,
        idAllocator: inout ChromeNodeIDAllocator
    ) -> [ChromeNode] {
        let children = (childrenByParent[parentItemID] ?? []).sorted(by: rootSort)
        return children.map { item in
            let guid = resolveGUID(for: item)
            let existing = existingIndex.byGUID[guid]

            if item.type == .folder {
                return ChromeNode(
                    children: buildChildren(parentItemID: item.id, childrenByParent: childrenByParent,
                                            existingIndex: existingIndex, idAllocator: &idAllocator),
                    dateAdded: existing?.dateAdded ?? chromeTimestamp(item.dateAdded ?? Date()),
                    dateModified: chromeTimestamp(item.dateModified ?? Date()),
                    guid: guid,
                    id: existing?.id ?? idAllocator.nextID(),
                    name: item.title,
                    type: "folder",
                    url: nil
                )
            }

            return ChromeNode(
                children: nil,
                dateAdded: existing?.dateAdded ?? chromeTimestamp(item.dateAdded ?? Date()),
                dateModified: nil,
                guid: guid,
                id: existing?.id ?? idAllocator.nextID(),
                name: item.title,
                type: "url",
                url: item.url
            )
        }
    }

    private func resolveGUID(for item: BookmarkItem) -> String {
        guard let clientID, let mapped = item.identifierMap[clientID], !mapped.isEmpty else {
            return item.id
        }
        return mapped
    }

    private func chromeTimestamp(_ date: Date) -> String {
        let microseconds = (date.timeIntervalSince1970 + 11_644_473_600.0) * 1_000_000.0
        return String(Int64(microseconds))
    }
}

private struct ExistingNodeInfo {
    let id: String
    let dateAdded: String?
}

private struct ExistingNodeIndex {
    var byGUID: [String: ExistingNodeInfo] = [:]
    var maxNumericID: Int = 0

    init(roots: ChromeRoots) {
        index(node: roots.bookmarkBar)
        index(node: roots.other)
        index(node: roots.synced)
    }

    private mutating func index(node: ChromeNode) {
        byGUID[node.guid] = ExistingNodeInfo(id: node.id, dateAdded: node.dateAdded)
        if let numeric = Int(node.id) {
            maxNumericID = max(maxNumericID, numeric)
        }
        for child in node.children ?? [] {
            index(node: child)
        }
    }
}

private struct ChromeNodeIDAllocator {
    private var nextNumericID: Int

    init(startingAt: Int) {
        nextNumericID = max(startingAt, 1)
    }

    mutating func nextID() -> String {
        defer { nextNumericID += 1 }
        return String(nextNumericID)
    }
}
