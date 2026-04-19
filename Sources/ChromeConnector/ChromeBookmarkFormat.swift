import Foundation

struct ChromeBookmarksFile: Codable {
    let checksum: String
    let roots: ChromeRoots
    let version: Int
}

struct ChromeRoots: Codable {
    let bookmarkBar: ChromeNode
    let other: ChromeNode
    let synced: ChromeNode

    enum CodingKeys: String, CodingKey {
        case bookmarkBar = "bookmark_bar"
        case other
        case synced
    }
}

struct ChromeNode: Codable {
    let children: [ChromeNode]?
    let dateAdded: String?
    let dateModified: String?
    let guid: String
    let id: String
    let name: String
    let type: String
    let url: String?

    enum CodingKeys: String, CodingKey {
        case children
        case dateAdded = "date_added"
        case dateModified = "date_modified"
        case guid
        case id
        case name
        case type
        case url
    }
}
