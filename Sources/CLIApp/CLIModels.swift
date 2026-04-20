import Foundation
import SyncEngine

public enum CLIError: Error, Equatable {
    case invalidArguments(String)
    case missingRequiredPath(String)
    case configNotFound(String)
    case purgeDeclined
}

extension CLIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidArguments(message):
            message
        case let .missingRequiredPath(message):
            "missing required path: \(message)"
        case let .configNotFound(path):
            "config file not found: \(path)"
        case .purgeDeclined:
            "reset --purge-store aborted by user"
        }
    }
}

public enum DirectionSetting: String {
    case importOnly = "import-only"
    case exportOnly = "export-only"
    case both

    var syncDirection: SyncDirection {
        switch self {
        case .importOnly:
            .importOnly
        case .exportOnly:
            .exportOnly
        case .both:
            .both
        }
    }
}

public struct RuntimeConfig {
    public let writerClientID: String
    public let chromeClientID: String?
    public let safariClientID: String?
    public let chromeBookmarksURL: URL?
    public let safariBookmarksURL: URL?
    public let chromeSyncDirection: DirectionSetting
    public let safariSyncDirection: DirectionSetting
    public let storeFileURL: URL
    public let snapshotsDirectoryURL: URL
    public let stateDirectoryURL: URL
    public let sortAfterImport: Bool
    public let safeSyncLimit: Int
    public let logFileURL: URL

    public init(
        writerClientID: String,
        chromeClientID: String?,
        safariClientID: String?,
        chromeBookmarksURL: URL?,
        safariBookmarksURL: URL?,
        chromeSyncDirection: DirectionSetting,
        safariSyncDirection: DirectionSetting,
        storeFileURL: URL,
        snapshotsDirectoryURL: URL,
        stateDirectoryURL: URL,
        sortAfterImport: Bool,
        safeSyncLimit: Int,
        logFileURL: URL
    ) {
        self.writerClientID = writerClientID
        self.chromeClientID = chromeClientID
        self.safariClientID = safariClientID
        self.chromeBookmarksURL = chromeBookmarksURL
        self.safariBookmarksURL = safariBookmarksURL
        self.chromeSyncDirection = chromeSyncDirection
        self.safariSyncDirection = safariSyncDirection
        self.storeFileURL = storeFileURL
        self.snapshotsDirectoryURL = snapshotsDirectoryURL
        self.stateDirectoryURL = stateDirectoryURL
        self.sortAfterImport = sortAfterImport
        self.safeSyncLimit = safeSyncLimit
        self.logFileURL = logFileURL
    }

    func validateForSync() throws {
        if safeSyncLimit < 0 {
            throw CLIError.invalidArguments("safe_sync_limit must be >= 0")
        }
        try validateIdentity()
        try validateBrowser(
            clientID: chromeClientID,
            bookmarksURL: chromeBookmarksURL,
            direction: chromeSyncDirection,
            browserLabel: "chrome"
        )
        try validateBrowser(
            clientID: safariClientID,
            bookmarksURL: safariBookmarksURL,
            direction: safariSyncDirection,
            browserLabel: "safari"
        )
    }

    func validateForReset() throws {
        try validateIdentity()
    }

    private func validateIdentity() throws {
        guard !writerClientID.isEmpty else {
            throw CLIError.missingRequiredPath("writer_client_id")
        }

        let hasAnyClientIdentity = [chromeClientID, safariClientID]
            .compactMap(\.self)
            .contains { !$0.isEmpty }
        if !hasAnyClientIdentity {
            throw CLIError.missingRequiredPath("client_id")
        }
    }

    private func validateBrowser(
        clientID: String?,
        bookmarksURL: URL?,
        direction: DirectionSetting,
        browserLabel: String
    ) throws {
        guard direction == .both || direction == .importOnly || direction == .exportOnly else { return }
        guard let clientID, !clientID.isEmpty else {
            throw CLIError.missingRequiredPath("\(browserLabel)_client_id")
        }
        guard let bookmarksURL, !bookmarksURL.path.isEmpty else {
            throw CLIError.missingRequiredPath("\(browserLabel)_bookmarks_path")
        }
    }
}
