import Foundation

struct ChromeBookmarksFile: Decodable {
    let checksum: String
    let roots: ChromeRoots
    let version: Int
}

struct ChromeRoots: Decodable {
    let bookmarkBar: ChromeNode
    let other: ChromeNode
    let synced: ChromeNode

    enum CodingKeys: String, CodingKey {
        case bookmarkBar = "bookmark_bar"
        case other
        case synced
    }
}

struct ChromeNode: Decodable {
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
