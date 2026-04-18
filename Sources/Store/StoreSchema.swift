import BookmarkModel
import Foundation

public struct StoreDocument: Sendable, Codable, Equatable {
    public let metadata: StoreMetadata
    public let items: [BookmarkItem]

    public init(metadata: StoreMetadata, items: [BookmarkItem]) {
        self.metadata = metadata
        self.items = items
    }
}

public struct StoreMetadata: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public let storeRevision: Int
    public let writtenByClientID: String
    public let updatedAt: Date
    public let clients: [StoreClient]

    public init(
        schemaVersion: Int,
        storeRevision: Int,
        writtenByClientID: String,
        updatedAt: Date,
        clients: [StoreClient]
    ) {
        self.schemaVersion = schemaVersion
        self.storeRevision = storeRevision
        self.writtenByClientID = writtenByClientID
        self.updatedAt = updatedAt
        self.clients = clients
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case storeRevision = "store_revision"
        case writtenByClientID = "written_by_client_id"
        case updatedAt = "updated_at"
        case clients
    }
}

public struct StoreClient: Sendable, Codable, Equatable {
    public let clientID: String
    public let browser: StoreBrowser
    public let platform: StorePlatform
    public let profileHint: String?
    public let status: StoreClientStatus

    public init(
        clientID: String,
        browser: StoreBrowser,
        platform: StorePlatform,
        profileHint: String? = nil,
        status: StoreClientStatus
    ) {
        self.clientID = clientID
        self.browser = browser
        self.platform = platform
        self.profileHint = profileHint
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case browser
        case platform
        case profileHint = "profile_hint"
        case status
    }
}

public enum StoreBrowser: String, Sendable, Codable {
    case chrome
    case safari
}

public enum StorePlatform: String, Sendable, Codable {
    case macos
}

public enum StoreClientStatus: String, Sendable, Codable {
    case active
    case removed
    case unavailable
}
