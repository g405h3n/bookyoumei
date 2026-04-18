import Foundation

public enum BookmarkItemType: String, Codable, Sendable {
    case folder
    case bookmark
}

public struct BookmarkItem: Sendable, Equatable {
    public let id: String
    public let type: BookmarkItemType
    public let parentID: String?
    public let position: Int
    public let title: String
    public let url: String?
    public let dateAdded: Date?
    public let dateModified: Date?
    public let identifierMap: [String: String]

    public init(
        id: String,
        type: BookmarkItemType,
        parentID: String?,
        position: Int,
        title: String,
        url: String? = nil,
        dateAdded: Date? = nil,
        dateModified: Date? = nil,
        identifierMap: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.parentID = parentID
        self.position = position
        self.title = title
        self.url = url
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.identifierMap = identifierMap
    }
}
