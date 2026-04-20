import BookmarkModel
import ChromeConnector
import Foundation
import SafariConnector
import Store

public protocol BrowserSyncAdapter {
    func read(config: SyncBrowserConfig) throws -> [BookmarkItem]
    func write(items: [BookmarkItem], config: SyncBrowserConfig) throws
}

public protocol BookmarkStoreClient {
    func load() throws -> StoreDocument?
    func write(
        items: [BookmarkItem],
        writerClientID: String,
        clients: [StoreClient],
        expectedStoreRevision: Int?,
        now: Date
    ) throws -> StoreDocument
}

extension BookmarkStore: BookmarkStoreClient {}

public struct ChromeSyncAdapter: BrowserSyncAdapter {
    public init() {}

    public func read(config: SyncBrowserConfig) throws -> [BookmarkItem] {
        try ChromeBookmarkReader(clientID: config.clientID).read(from: config.bookmarksFileURL)
    }

    public func write(items: [BookmarkItem], config: SyncBrowserConfig) throws {
        try ChromeBookmarkWriter(clientID: config.clientID).write(items: items, to: config.bookmarksFileURL)
    }
}

public struct SafariSyncAdapter: BrowserSyncAdapter {
    public init() {}

    public func read(config: SyncBrowserConfig) throws -> [BookmarkItem] {
        try SafariBookmarkReader(clientID: config.clientID).read(from: config.bookmarksFileURL)
    }

    public func write(items: [BookmarkItem], config: SyncBrowserConfig) throws {
        try SafariBookmarkWriter(clientID: config.clientID).write(items: items, to: config.bookmarksFileURL)
    }
}
