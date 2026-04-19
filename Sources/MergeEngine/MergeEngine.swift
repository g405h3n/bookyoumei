import BookmarkModel
import Foundation

public enum MergeMode: Sendable {
    case bootstrap
    case steadyState
}

public struct MergeStats: Sendable, Equatable {
    public let matchedCount: Int
    public let addedCount: Int
    public let updatedCount: Int

    public init(matchedCount: Int, addedCount: Int, updatedCount: Int) {
        self.matchedCount = matchedCount
        self.addedCount = addedCount
        self.updatedCount = updatedCount
    }
}

public struct MergeResult: Sendable, Equatable {
    public let mergedItems: [BookmarkItem]
    public let localDeletionCandidateIDs: [String]
    public let stats: MergeStats

    public init(mergedItems: [BookmarkItem], localDeletionCandidateIDs: [String], stats: MergeStats) {
        self.mergedItems = mergedItems
        self.localDeletionCandidateIDs = localDeletionCandidateIDs
        self.stats = stats
    }
}

public struct MergeEngine: Sendable {
    private let normalizer: URLNormalizer

    public init(normalizer: URLNormalizer = URLNormalizer()) {
        self.normalizer = normalizer
    }

    public func merge(
        canonicalItems: [BookmarkItem],
        localItems: [BookmarkItem],
        clientID: String,
        mode: MergeMode
    ) -> MergeResult {
        let state = mergeState(canonicalItems: canonicalItems, localItems: localItems, clientID: clientID)
        let mergedItems = Array(state.canonicalByID.values).sorted(by: canonicalSort)

        let deletionCandidates = mode == .steadyState
            ? deletionCandidatesForExport(canonicalItems: mergedItems, targetItems: localItems, clientID: clientID)
            : []

        return MergeResult(
            mergedItems: mergedItems,
            localDeletionCandidateIDs: deletionCandidates,
            stats: state.stats
        )
    }

    public func deletionCandidatesForExport(
        canonicalItems: [BookmarkItem],
        targetItems: [BookmarkItem],
        clientID: String
    ) -> [String] {
        let targetByID = Dictionary(uniqueKeysWithValues: targetItems.map { ($0.id, $0) })
        let matchedIDs = matchTargetItemsForCanonical(
            canonicalItems: canonicalItems,
            targetByID: targetByID,
            clientID: clientID,
            normalizer: normalizer
        )
        let excludedIDs = excludedTargetSubtreeIDs(targetItems: targetItems)

        return targetItems
            .filter { !matchedIDs.contains($0.id) }
            .filter { !($0.type == .folder && $0.parentID == nil) }
            .filter { !excludedIDs.contains($0.id) }
            .map(\.id)
            .sorted()
    }

    private func mergeState(
        canonicalItems: [BookmarkItem],
        localItems: [BookmarkItem],
        clientID: String
    ) -> MergeState {
        var canonicalByID = Dictionary(uniqueKeysWithValues: canonicalItems.map { ($0.id, $0) })
        let sortedLocalItems = sortByDepthThenPosition(items: localItems)
        var localToCanonicalID: [String: String] = [:]

        var matchedCount = 0
        var addedCount = 0
        var updatedCount = 0

        for localItem in sortedLocalItems {
            let canonicalParentID = localItem.parentID.flatMap { localToCanonicalID[$0] }

            if let matchedID = matchCanonicalItem(
                localItem: localItem,
                canonicalParentID: canonicalParentID,
                clientID: clientID,
                canonicalByID: canonicalByID,
                normalizer: normalizer
            ), let existing = canonicalByID[matchedID] {
                matchedCount += 1
                localToCanonicalID[localItem.id] = matchedID

                let updated = mergedItem(
                    existing: existing,
                    localItem: localItem,
                    canonicalParentID: canonicalParentID,
                    clientID: clientID,
                    normalizer: normalizer
                )

                if updated != existing {
                    updatedCount += 1
                    canonicalByID[matchedID] = updated
                }
            } else {
                addedCount += 1
                let newID = generatedCanonicalID(
                    localItem: localItem,
                    canonicalParentID: canonicalParentID,
                    canonicalByID: canonicalByID
                )
                localToCanonicalID[localItem.id] = newID
                canonicalByID[newID] = addedCanonicalItem(
                    canonicalID: newID,
                    localItem: localItem,
                    canonicalParentID: canonicalParentID,
                    clientID: clientID,
                    normalizer: normalizer
                )
            }
        }

        return MergeState(
            canonicalByID: canonicalByID,
            stats: MergeStats(matchedCount: matchedCount, addedCount: addedCount, updatedCount: updatedCount)
        )
    }
}

private struct MergeState {
    let canonicalByID: [String: BookmarkItem]
    let stats: MergeStats
}

private func addedCanonicalItem(
    canonicalID: String,
    localItem: BookmarkItem,
    canonicalParentID: String?,
    clientID: String,
    normalizer: URLNormalizer
) -> BookmarkItem {
    var identifierMap = localItem.identifierMap
    identifierMap[clientID] = localItem.id

    return BookmarkItem(
        id: canonicalID,
        type: localItem.type,
        parentID: canonicalParentID,
        position: localItem.position,
        title: localItem.title,
        url: normalizedBookmarkURL(for: localItem, normalizer: normalizer),
        dateAdded: localItem.dateAdded,
        dateModified: localItem.dateModified,
        identifierMap: identifierMap
    )
}

private func mergedItem(
    existing: BookmarkItem,
    localItem: BookmarkItem,
    canonicalParentID: String?,
    clientID: String,
    normalizer: URLNormalizer
) -> BookmarkItem {
    var identifierMap = existing.identifierMap
    identifierMap.merge(localItem.identifierMap) { _, incoming in incoming }
    identifierMap[clientID] = localItem.id

    return BookmarkItem(
        id: existing.id,
        type: existing.type,
        parentID: canonicalParentID,
        position: localItem.position,
        title: localItem.title,
        url: normalizedBookmarkURL(for: localItem, normalizer: normalizer) ?? existing.url,
        dateAdded: localItem.dateAdded ?? existing.dateAdded,
        dateModified: maxDate(existing.dateModified, localItem.dateModified),
        identifierMap: identifierMap
    )
}

private func matchCanonicalItem(
    localItem: BookmarkItem,
    canonicalParentID: String?,
    clientID: String,
    canonicalByID: [String: BookmarkItem],
    normalizer: URLNormalizer
) -> String? {
    let canonicalItems = Array(canonicalByID.values)

    if let identifierMatch = canonicalItems.first(where: { $0.identifierMap[clientID] == localItem.id }) {
        return identifierMatch.id
    }

    if localItem.type == .folder {
        return canonicalItems.first(where: {
            $0.type == .folder
                && $0.parentID == canonicalParentID
                && $0.title.caseInsensitiveCompare(localItem.title) == .orderedSame
        })?.id
    }

    guard localItem.type == .bookmark, let localURL = localItem.url else {
        return nil
    }

    let normalizedLocalURL = normalizer.comparisonNormalized(localURL)
    let candidates = canonicalItems.filter { item in
        guard item.type == .bookmark, let url = item.url else { return false }
        return normalizer.comparisonNormalized(url) == normalizedLocalURL
    }

    if let parentAndTitleMatch = candidates.first(where: {
        $0.parentID == canonicalParentID && $0.title.caseInsensitiveCompare(localItem.title) == .orderedSame
    }) {
        return parentAndTitleMatch.id
    }

    if let parentMatch = candidates.first(where: { $0.parentID == canonicalParentID }) {
        return parentMatch.id
    }

    if let titleMatch = candidates.first(where: { $0.title.caseInsensitiveCompare(localItem.title) == .orderedSame }) {
        return titleMatch.id
    }

    return candidates.first?.id
}

private func matchTargetItemsForCanonical(
    canonicalItems: [BookmarkItem],
    targetByID: [String: BookmarkItem],
    clientID: String,
    normalizer: URLNormalizer
) -> Set<String> {
    let targetItems = Array(targetByID.values)
    let canonicalParentPathByID = parentPathMap(items: canonicalItems)
    let targetParentPathByID = parentPathMap(items: targetItems)

    var matchedTargetIDs = Set<String>()

    for canonicalItem in canonicalItems {
        if let targetID = canonicalItem.identifierMap[clientID], targetByID[targetID] != nil {
            matchedTargetIDs.insert(targetID)
            continue
        }

        let canonicalParentPath = canonicalParentPathByID[canonicalItem.id]

        if canonicalItem.type == .folder {
            let folderCandidates = targetItems.filter { targetItem in
                targetItem.type == .folder
                    && targetParentPathByID[targetItem.id] == canonicalParentPath
                    && targetItem.title.caseInsensitiveCompare(canonicalItem.title) == .orderedSame
            }
            if let selected = deterministicallySelectedCandidate(from: folderCandidates) {
                matchedTargetIDs.insert(selected.id)
            }
            continue
        }

        guard canonicalItem.type == .bookmark, let canonicalURL = canonicalItem.url else {
            continue
        }
        let canonicalNormalizedURL = normalizer.comparisonNormalized(canonicalURL)

        let candidates = targetItems.filter { targetItem in
            guard targetItem.type == .bookmark, let targetURL = targetItem.url else { return false }
            if normalizer.comparisonNormalized(targetURL) != canonicalNormalizedURL {
                return false
            }
            return targetParentPathByID[targetItem.id] == canonicalParentPath
        }

        let titleMatches = candidates.filter {
            $0.title.caseInsensitiveCompare(canonicalItem.title) == .orderedSame
        }
        if let titleMatch = deterministicallySelectedCandidate(from: titleMatches) {
            matchedTargetIDs.insert(titleMatch.id)
        } else if let selected = deterministicallySelectedCandidate(from: candidates) {
            matchedTargetIDs.insert(selected.id)
        }
    }

    return matchedTargetIDs
}

private func deterministicallySelectedCandidate(from candidates: [BookmarkItem]) -> BookmarkItem? {
    candidates.sorted { left, right in
        if left.id != right.id {
            return left.id < right.id
        }
        return left.position < right.position
    }.first
}

private func excludedTargetSubtreeIDs(targetItems: [BookmarkItem]) -> Set<String> {
    let excludedRootIDs = Set<String>(
        targetItems.compactMap { item in
            guard item.type == .folder, item.parentID == nil else {
                return nil
            }
            let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedTitle == "mobile bookmarks" || item.id == "synced" {
                return item.id
            }
            return nil
        }
    )
    if excludedRootIDs.isEmpty {
        return Set<String>()
    }

    let childrenByParent = Dictionary(grouping: targetItems, by: \.parentID)
    var excludedIDs = excludedRootIDs
    var queue = Array(excludedRootIDs)

    while let current = queue.popLast() {
        let children = childrenByParent[current] ?? []
        for child in children where !excludedIDs.contains(child.id) {
            excludedIDs.insert(child.id)
            queue.append(child.id)
        }
    }

    return excludedIDs
}

private func normalizedBookmarkURL(for item: BookmarkItem, normalizer: URLNormalizer) -> String? {
    guard item.type == .bookmark, let url = item.url else {
        return nil
    }
    return normalizer.storageNormalized(url)
}

private func parentPathMap(items: [BookmarkItem]) -> [String: String] {
    let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    var cache: [String: String] = [:]

    func path(for itemID: String) -> String {
        if let cached = cache[itemID] {
            return cached
        }
        guard let item = byID[itemID] else {
            return ""
        }

        let value: String
        if let parentID = item.parentID, let parent = byID[parentID] {
            let parentPath = path(for: parentID)
            value = parentPath.isEmpty ? parent.title : "\(parentPath)/\(parent.title)"
        } else {
            value = ""
        }

        cache[itemID] = value
        return value
    }

    var result: [String: String] = [:]
    for item in items {
        result[item.id] = path(for: item.id)
    }

    return result
}

private func sortByDepthThenPosition(items: [BookmarkItem]) -> [BookmarkItem] {
    let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

    func depth(of item: BookmarkItem) -> Int {
        var depth = 0
        var cursor = item.parentID
        while let current = cursor, let parent = byID[current] {
            depth += 1
            cursor = parent.parentID
        }
        return depth
    }

    return items.sorted {
        let leftDepth = depth(of: $0)
        let rightDepth = depth(of: $1)
        if leftDepth != rightDepth {
            return leftDepth < rightDepth
        }
        if $0.position != $1.position {
            return $0.position < $1.position
        }
        return $0.id < $1.id
    }
}

private func generatedCanonicalID(
    localItem: BookmarkItem,
    canonicalParentID: String?,
    canonicalByID: [String: BookmarkItem]
) -> String {
    guard localItem.type == .folder, canonicalParentID == nil,
          let hardFolderID = hardFolderCanonicalID(title: localItem.title)
    else {
        return UUID().uuidString
    }

    if let existing = canonicalByID[hardFolderID], existing.type == .folder {
        return existing.id
    }
    return hardFolderID
}

private func hardFolderCanonicalID(title: String) -> String? {
    let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    switch normalized {
    case "bookmarks bar", "favorites bar", "favoritesbar":
        return "bookmarks_bar"
    case "other bookmarks":
        return "other_bookmarks"
    default:
        return nil
    }
}

private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    switch (lhs, rhs) {
    case let (.some(left), .some(right)):
        max(left, right)
    case let (.some(left), .none):
        left
    case let (.none, .some(right)):
        right
    case (.none, .none):
        nil
    }
}

private func canonicalSort(_ lhs: BookmarkItem, _ rhs: BookmarkItem) -> Bool {
    if lhs.parentID == nil, rhs.parentID != nil {
        return true
    }
    if lhs.parentID != nil, rhs.parentID == nil {
        return false
    }
    if lhs.parentID != rhs.parentID {
        return (lhs.parentID ?? "") < (rhs.parentID ?? "")
    }
    if lhs.position != rhs.position {
        return lhs.position < rhs.position
    }
    return lhs.id < rhs.id
}
