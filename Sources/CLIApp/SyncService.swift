import Foundation
import Store
import SyncEngine

public protocol SyncServicing {
    func runSync(config: RuntimeConfig) throws -> SyncCycleResult
}

public final class SyncService: SyncServicing {
    private let antiChurnStateStore: any AntiChurnStateStore

    public init(antiChurnStateStore: any AntiChurnStateStore = InMemoryAntiChurnStateStore()) {
        self.antiChurnStateStore = antiChurnStateStore
    }

    public func runSync(config: RuntimeConfig) throws -> SyncCycleResult {
        let coordinator = SyncCoordinator(
            store: BookmarkStore(
                fileURL: config.storeFileURL,
                snapshotsDirectoryURL: config.snapshotsDirectoryURL
            ),
            adapters: BrowserSyncRuntimeFactory.makeAdapters(),
            antiChurnStateStore: antiChurnStateStore
        )

        let browserConfigs = BrowserSyncRuntimeFactory.buildSyncBrowserConfigs(config: config)
        let request = SyncCycleRequest(
            writerClientID: config.writerClientID,
            browsers: browserConfigs,
            sortAfterImport: config.sortAfterImport,
            safeSyncLimit: config.safeSyncLimit,
            now: Date()
        )

        return try coordinator.runCycle(request: request)
    }
}
