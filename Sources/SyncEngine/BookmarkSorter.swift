import BookmarkModel

public struct BookmarkSorter {
    public init() {}

    func sorted(items: [BookmarkItem]) -> [BookmarkItem] {
        let childrenByParent = Dictionary(grouping: items.filter { $0.parentID != nil }, by: \.parentID)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        var rewritten: [String: BookmarkItem] = [:]

        for (parentID, children) in childrenByParent {
            let sortedChildren = children.sorted(by: sortByTitleThenID)
            for (index, child) in sortedChildren.enumerated() {
                rewritten[child.id] = BookmarkItem(
                    id: child.id,
                    type: child.type,
                    parentID: parentID,
                    position: index,
                    title: child.title,
                    url: child.url,
                    dateAdded: child.dateAdded,
                    dateModified: child.dateModified,
                    identifierMap: child.identifierMap
                )
            }
        }

        return items.map { rewritten[$0.id] ?? $0 }.sorted(by: { lhs, rhs in
            if lhs.parentID == nil, rhs.parentID != nil { return true }
            if lhs.parentID != nil, rhs.parentID == nil { return false }
            if lhs.parentID != rhs.parentID { return (lhs.parentID ?? "") < (rhs.parentID ?? "") }
            if lhs.position != rhs.position { return lhs.position < rhs.position }
            let lhsParentDepth = parentDepth(itemID: lhs.id, byID: byID)
            let rhsParentDepth = parentDepth(itemID: rhs.id, byID: byID)
            if lhsParentDepth != rhsParentDepth { return lhsParentDepth < rhsParentDepth }
            return lhs.id < rhs.id
        })
    }

    private func sortByTitleThenID(_ lhs: BookmarkItem, _ rhs: BookmarkItem) -> Bool {
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private func parentDepth(itemID: String, byID: [String: BookmarkItem]) -> Int {
        var depth = 0
        var cursor = byID[itemID]?.parentID
        while let node = cursor, let parent = byID[node] {
            depth += 1
            cursor = parent.parentID
        }
        return depth
    }
}
