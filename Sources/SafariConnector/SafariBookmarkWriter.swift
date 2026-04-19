import BookmarkModel
import Foundation

public enum SafariBookmarkWriterError: Error, Equatable {
    case invalidFormat
    case missingHardFolder(String)
    case duplicateHardFolder(String)
    case orphanedParentReference(itemID: String, parentID: String)
    case nonFolderParentReference(itemID: String, parentID: String)
    case missingBookmarkURL(itemID: String)
}

// swiftlint:disable type_body_length
public struct SafariBookmarkWriter: Sendable {
    public let clientID: String?

    public init(clientID: String? = nil) {
        self.clientID = clientID
    }

    // swiftlint:disable function_body_length
    public func write(items: [BookmarkItem], to fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)

        guard var root = plist as? [String: Any] else {
            throw SafariBookmarkWriterError.invalidFormat
        }

        let topLevelChildren = childNodes(from: root)
        let expectedFavoritesUUID = expectedFavoritesUUID(from: items, topLevelChildren: topLevelChildren)
        let favoritesIndex = topLevelChildren.firstIndex { node in
            isFavoritesRoot(node, expectedUUID: expectedFavoritesUUID)
        }
        let existingFavoritesNode = favoritesIndex.map { topLevelChildren[$0] }
        let excludedUUIDs = detectExcludedTopLevelUUIDs(from: topLevelChildren)
        let existingManagedOtherNodes = topLevelChildren.enumerated().compactMap { element -> [String: Any]? in
            let (index, node) = element
            if favoritesIndex == index { return nil }
            if isExcludedTopLevelNode(node, excludedUUIDs: excludedUUIDs) { return nil }
            return node
        }

        let favoritesRoot = try requireHardRoot(
            from: items,
            expectedUUID: expectedFavoritesUUID,
            aliases: ["favorites bar", "favoritesbar"],
            key: "bookmarks_bar"
        )
        let otherRoot = try requireHardRoot(
            from: items,
            expectedUUID: nil,
            aliases: ["other bookmarks", "other_bookmarks", "safari-other-bookmarks"],
            key: "other_bookmarks"
        )

        let childrenByParent = Dictionary(grouping: items.filter { $0.parentID != nil }, by: \.parentID)
        try validateItems(items)
        let favoritesChildren = buildChildren(
            parentItemID: favoritesRoot.id,
            childrenByParent: childrenByParent,
            existingChildren: childNodes(from: existingFavoritesNode)
        )
        let otherChildren = buildChildren(
            parentItemID: otherRoot.id,
            childrenByParent: childrenByParent,
            existingChildren: existingManagedOtherNodes
        )

        let updatedFavorites = makeFavoritesNode(
            existing: existingFavoritesNode,
            fallbackItem: favoritesRoot,
            children: favoritesChildren
        )

        root["Children"] = rebuildTopLevelChildren(
            existingTopLevel: topLevelChildren,
            updatedFavorites: updatedFavorites,
            otherChildren: otherChildren,
            expectedFavoritesUUID: expectedFavoritesUUID,
            excludedUUIDs: excludedUUIDs
        )

        let encoded = try PropertyListSerialization.data(fromPropertyList: root, format: format, options: 0)
        try encoded.write(to: fileURL, options: .atomic)
    }

    // swiftlint:enable function_body_length

    public static func defaultBookmarksURL() -> URL {
        SafariBookmarkReader.defaultBookmarksURL()
    }

    // MARK: - Private

    private func requireHardRoot(
        from items: [BookmarkItem],
        expectedUUID: String?,
        aliases: Set<String>,
        key: String
    ) throws -> BookmarkItem {
        let topLevelFolders = items.filter { $0.type == .folder && $0.parentID == nil }

        if let expectedUUID, let clientID {
            let matches = topLevelFolders
                .filter { $0.identifierMap[clientID] == expectedUUID }
                .sorted(by: rootSort)
            if matches.count > 1 {
                throw SafariBookmarkWriterError.duplicateHardFolder(key)
            }
            if let byIdentifierMap = matches.first {
                return byIdentifierMap
            }
        }

        if let expectedUUID {
            let matches = topLevelFolders
                .filter { $0.id == expectedUUID }
                .sorted(by: rootSort)
            if matches.count > 1 {
                throw SafariBookmarkWriterError.duplicateHardFolder(key)
            }
            if let byCanonicalID = matches.first {
                return byCanonicalID
            }
        }

        let byAlias = topLevelFolders
            .filter { aliases.contains($0.title.lowercased()) }
            .sorted(by: rootSort)
        if byAlias.count > 1 {
            throw SafariBookmarkWriterError.duplicateHardFolder(key)
        }
        if let matched = byAlias.first {
            return matched
        }

        throw SafariBookmarkWriterError.missingHardFolder(key)
    }

    private func rootSort(_ lhs: BookmarkItem, _ rhs: BookmarkItem) -> Bool {
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    private func makeFavoritesNode(
        existing: [String: Any]?,
        fallbackItem: BookmarkItem,
        children: [[String: Any]]
    ) -> [String: Any] {
        var node = existing ?? [:]
        node["WebBookmarkType"] = "WebBookmarkTypeList"
        node["Title"] = nodeTitle(existing) ?? fallbackItem.title
        node["WebBookmarkUUID"] = resolveUUID(for: fallbackItem, existingNode: existing)
        node["Children"] = children
        return node
    }

    private func rebuildTopLevelChildren(
        existingTopLevel: [[String: Any]],
        updatedFavorites: [String: Any],
        otherChildren: [[String: Any]],
        expectedFavoritesUUID: String?,
        excludedUUIDs: Set<String>
    ) -> [[String: Any]] {
        let favoritesMatch: ([String: Any]) -> Bool = { node in
            isFavoritesRoot(node, expectedUUID: expectedFavoritesUUID)
        }
        let excludedMatch: ([String: Any]) -> Bool = { node in
            isExcludedTopLevelNode(node, excludedUUIDs: excludedUUIDs)
        }

        let managedIndexes = existingTopLevel.enumerated().compactMap { index, node in
            if !favoritesMatch(node), !excludedMatch(node) {
                return index
            }
            return nil
        }

        var result: [[String: Any]] = []
        var favoritesInserted = false

        for node in existingTopLevel {
            if favoritesMatch(node) {
                if !favoritesInserted {
                    result.append(updatedFavorites)
                    favoritesInserted = true
                }
                continue
            }
            if excludedMatch(node) {
                result.append(node)
            }
        }

        if !favoritesInserted {
            result.insert(updatedFavorites, at: 0)
            favoritesInserted = true
        }

        let insertionIndex: Int = if let firstManaged = managedIndexes.first {
            existingTopLevel[..<firstManaged].reduce(into: 0) { count, node in
                if favoritesMatch(node) || excludedMatch(node) {
                    count += 1
                }
            }
        } else if let favoritesIndex = result.firstIndex(where: favoritesMatch) {
            favoritesIndex + 1
        } else {
            result.count
        }

        result.insert(contentsOf: otherChildren, at: insertionIndex)
        return result
    }

    private func buildChildren(
        parentItemID: String,
        childrenByParent: [String?: [BookmarkItem]],
        existingChildren: [[String: Any]]
    ) -> [[String: Any]] {
        let children = (childrenByParent[parentItemID] ?? []).sorted(by: rootSort)
        var matcher = ExistingNodeMatcher(nodes: existingChildren)

        // swiftlint:disable trailing_comma
        return children.map { item in
            let existingMatch = matcher.takeMatch(for: item)
            let uuid = resolveUUID(for: item, existingNode: existingMatch)

            if item.type == .folder {
                let nested = buildChildren(
                    parentItemID: item.id,
                    childrenByParent: childrenByParent,
                    existingChildren: childNodes(from: existingMatch)
                )
                return [
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": item.title,
                    "WebBookmarkUUID": uuid,
                    "Children": nested,
                ]
            }

            return [
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "Title": item.title,
                "URIDictionary": [
                    "title": item.title,
                ],
                "URLString": item.url ?? "",
                "WebBookmarkUUID": uuid,
            ]
        }
        // swiftlint:enable trailing_comma
    }

    private func resolveUUID(for item: BookmarkItem, existingNode: [String: Any]?) -> String {
        if let clientID, let mapped = item.identifierMap[clientID], !mapped.isEmpty {
            return mapped
        }
        if let existingUUID = nodeUUID(existingNode), !existingUUID.isEmpty {
            return existingUUID
        }
        return UUID().uuidString.lowercased()
    }

    private func validateItems(_ items: [BookmarkItem]) throws {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let allIDs = Set(items.map(\.id))
        for item in items {
            if item.type == .bookmark {
                let url = item.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if url.isEmpty {
                    throw SafariBookmarkWriterError.missingBookmarkURL(itemID: item.id)
                }
            }

            if let parentID = item.parentID {
                guard allIDs.contains(parentID) else {
                    throw SafariBookmarkWriterError.orphanedParentReference(itemID: item.id, parentID: parentID)
                }
                if let parent = byID[parentID], parent.type != .folder {
                    throw SafariBookmarkWriterError.nonFolderParentReference(itemID: item.id, parentID: parentID)
                }
            }
        }
    }

    private func childNodes(from node: [String: Any]?) -> [[String: Any]] {
        guard let node else { return [] }
        return (node["Children"] as? [[String: Any]]) ?? []
    }

    private func isFavoritesRoot(_ node: [String: Any], expectedUUID: String?) -> Bool {
        if let expectedUUID, nodeUUID(node) == expectedUUID {
            return true
        }
        let title = nodeTitle(node)?.lowercased() ?? ""
        let type = (node["WebBookmarkType"] as? String)?.lowercased() ?? ""
        return (title == "favorites bar" || title == "favoritesbar") && type == "webbookmarktypelist"
    }

    private func isExcludedTopLevelNode(_ node: [String: Any], excludedUUIDs: Set<String>) -> Bool {
        if let uuid = nodeUUID(node), excludedUUIDs.contains(uuid) {
            return true
        }
        let title = nodeTitle(node)?.lowercased() ?? ""
        if title == "reading list" || title == "com.apple.readinglist" {
            return true
        }
        return title == "bookmarks menu" || title == "bookmarksmenu"
    }

    private func expectedFavoritesUUID(from items: [BookmarkItem], topLevelChildren: [[String: Any]]) -> String? {
        let topLevelUUIDs = Set(topLevelChildren.compactMap(nodeUUID))
        let topLevelFolders = items.filter { $0.type == .folder && $0.parentID == nil }

        if let clientID {
            let mapped = Set(topLevelFolders.compactMap { $0.identifierMap[clientID] })
            let intersection = mapped.intersection(topLevelUUIDs)
            if intersection.count == 1 {
                return intersection.first
            }
        }

        if let aliasMatched = topLevelChildren.first(where: { node in
            let title = nodeTitle(node)?.lowercased() ?? ""
            return title == "favorites bar" || title == "favoritesbar"
        }) {
            return nodeUUID(aliasMatched)
        }
        return nil
    }

    private func detectExcludedTopLevelUUIDs(from topLevelChildren: [[String: Any]]) -> Set<String> {
        var detected: Set<String> = []
        for node in topLevelChildren {
            if isKnownExcludedUUID(nodeUUID(node)) || matchesExcludedTitle(node) {
                if let uuid = nodeUUID(node), !uuid.isEmpty {
                    detected.insert(uuid)
                }
            }
        }
        return detected
    }

    private func matchesExcludedTitle(_ node: [String: Any]) -> Bool {
        let title = nodeTitle(node)?.lowercased() ?? ""
        if title == "reading list" || title == "com.apple.readinglist" {
            return true
        }
        return title == "bookmarks menu" || title == "bookmarksmenu"
    }

    private func isKnownExcludedUUID(_ uuid: String?) -> Bool {
        guard let uuid else { return false }
        return Self.knownExcludedTopLevelUUIDs.contains(uuid)
    }

    // swiftlint:disable trailing_comma
    private static let knownExcludedTopLevelUUIDs: Set<String> = [
        "reading-list-uuid",
        "bookmarks-menu-uuid",
        "com.apple.ReadingList",
        "com.apple.BookmarksMenu",
    ]
    // swiftlint:enable trailing_comma

    private func nodeTitle(_ node: [String: Any]?) -> String? {
        guard let node else { return nil }
        if let title = node["Title"] as? String {
            return title
        }
        if let uriDictionary = node["URIDictionary"] as? [String: Any] {
            return uriDictionary["title"] as? String
        }
        return nil
    }

    private func nodeUUID(_ node: [String: Any]?) -> String? {
        guard let node else { return nil }
        return node["WebBookmarkUUID"] as? String
    }
}

// swiftlint:enable type_body_length

private struct ExistingNodeSignature: Hashable {
    let type: BookmarkItemType
    let title: String
    let url: String
}

private struct ExistingNodeMatcher {
    private var buckets: [ExistingNodeSignature: [[String: Any]]] = [:]

    init(nodes: [[String: Any]]) {
        for node in nodes {
            guard let signature = Self.signature(for: node) else { continue }
            buckets[signature, default: []].append(node)
        }
    }

    mutating func takeMatch(for item: BookmarkItem) -> [String: Any]? {
        let signature = ExistingNodeSignature(
            type: item.type,
            title: item.title,
            url: item.url ?? ""
        )
        guard var nodes = buckets[signature], !nodes.isEmpty else { return nil }
        let first = nodes.removeFirst()
        buckets[signature] = nodes
        return first
    }

    private static func signature(for node: [String: Any]) -> ExistingNodeSignature? {
        let typeString = (node["WebBookmarkType"] as? String)?.lowercased() ?? ""
        let type: BookmarkItemType
        switch typeString {
        case "webbookmarktypelist":
            type = .folder
        case "webbookmarktypeleaf":
            type = .bookmark
        default:
            return nil
        }

        let title: String = {
            if let title = node["Title"] as? String { return title }
            if let uri = node["URIDictionary"] as? [String: Any], let title = uri["title"] as? String {
                return title
            }
            return ""
        }()

        return ExistingNodeSignature(type: type, title: title, url: (node["URLString"] as? String) ?? "")
    }
}
