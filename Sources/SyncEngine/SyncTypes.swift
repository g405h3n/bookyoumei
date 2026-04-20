import Foundation

public enum SyncBrowser: String, CaseIterable, Sendable {
    case chrome
    case safari
}

public enum SyncDirection: Sendable {
    case importOnly
    case exportOnly
    case both

    var isImportEnabled: Bool {
        self == .importOnly || self == .both
    }

    var isExportEnabled: Bool {
        self == .exportOnly || self == .both
    }
}

public struct SyncBrowserConfig: Sendable {
    public let browser: SyncBrowser
    public let clientID: String
    public let direction: SyncDirection
    public let bookmarksFileURL: URL

    public init(browser: SyncBrowser, clientID: String, direction: SyncDirection, bookmarksFileURL: URL) {
        self.browser = browser
        self.clientID = clientID
        self.direction = direction
        self.bookmarksFileURL = bookmarksFileURL
    }
}

public struct SyncCycleRequest: Sendable {
    public let writerClientID: String
    public let browsers: [SyncBrowserConfig]
    public let sortAfterImport: Bool
    public let now: Date

    public init(writerClientID: String, browsers: [SyncBrowserConfig], sortAfterImport: Bool, now: Date = Date()) {
        self.writerClientID = writerClientID
        self.browsers = browsers
        self.sortAfterImport = sortAfterImport
        self.now = now
    }
}

public struct SyncCycleResult: Sendable {
    public let didWriteStore: Bool
    public let storeRevision: Int?
    public let importedBrowsers: [SyncBrowser]
    public let exportedBrowsers: [SyncBrowser]
    public let skippedByAntiChurn: [SyncBrowser]

    public init(
        didWriteStore: Bool,
        storeRevision: Int?,
        importedBrowsers: [SyncBrowser],
        exportedBrowsers: [SyncBrowser],
        skippedByAntiChurn: [SyncBrowser]
    ) {
        self.didWriteStore = didWriteStore
        self.storeRevision = storeRevision
        self.importedBrowsers = importedBrowsers
        self.exportedBrowsers = exportedBrowsers
        self.skippedByAntiChurn = skippedByAntiChurn
    }
}
