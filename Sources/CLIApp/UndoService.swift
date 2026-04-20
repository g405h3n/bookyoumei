import Foundation
import Store
import SyncEngine

public struct UndoResult: Equatable {
    public let restoredRevision: Int
    public let exportedBrowsers: [SyncBrowser]

    public init(restoredRevision: Int, exportedBrowsers: [SyncBrowser]) {
        self.restoredRevision = restoredRevision
        self.exportedBrowsers = exportedBrowsers
    }
}

public protocol UndoServicing {
    func undo(config: RuntimeConfig) throws -> UndoResult
}

public final class UndoService: UndoServicing {
    private let storeClient: any BookmarkStoreClient
    private let adapters: [SyncBrowser: any BrowserSyncAdapter]

    public init(
        storeClient: any BookmarkStoreClient,
        adapters: [SyncBrowser: any BrowserSyncAdapter]
    ) {
        self.storeClient = storeClient
        self.adapters = adapters
    }

    public func undo(config: RuntimeConfig) throws -> UndoResult {
        guard let snapshot = try storeClient.loadLatestSnapshot() else {
            throw BookmarkStoreError.snapshotNotFound
        }

        let expectedRevision = try storeClient.load()?.metadata.storeRevision
        let restored = try storeClient.write(
            items: snapshot.items,
            writerClientID: config.writerClientID,
            clients: snapshot.metadata.clients,
            expectedStoreRevision: expectedRevision,
            now: Date()
        )

        let exportConfigs = BrowserSyncRuntimeFactory.buildExportBrowserConfigs(config: config)
        for config in exportConfigs {
            try adapter(for: config.browser).write(items: restored.items, config: config)
        }

        return UndoResult(
            restoredRevision: restored.metadata.storeRevision,
            exportedBrowsers: exportConfigs.map(\.browser)
        )
    }

    private func adapter(for browser: SyncBrowser) throws -> any BrowserSyncAdapter {
        guard let adapter = adapters[browser] else {
            throw SyncCoordinatorError.missingAdapter(browser)
        }
        return adapter
    }
}
