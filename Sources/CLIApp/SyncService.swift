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
        // swiftlint:disable trailing_comma
        let adapters: [SyncBrowser: any BrowserSyncAdapter] = [
            .chrome: ChromeSyncAdapter(),
            .safari: SafariSyncAdapter(),
        ]
        // swiftlint:enable trailing_comma

        let coordinator = SyncCoordinator(
            store: BookmarkStore(fileURL: config.storeFileURL),
            adapters: adapters,
            antiChurnStateStore: antiChurnStateStore
        )

        let browserConfigs = buildBrowserConfigs(config: config)
        let request = SyncCycleRequest(
            writerClientID: config.writerClientID,
            browsers: browserConfigs,
            sortAfterImport: config.sortAfterImport,
            safeSyncLimit: config.safeSyncLimit,
            now: Date()
        )

        return try coordinator.runCycle(request: request)
    }

    private func buildBrowserConfigs(config: RuntimeConfig) -> [SyncBrowserConfig] {
        var result: [SyncBrowserConfig] = []

        if let chromeClientID = config.chromeClientID, let chromeURL = config.chromeBookmarksURL {
            result.append(
                SyncBrowserConfig(
                    browser: .chrome,
                    clientID: chromeClientID,
                    direction: config.chromeSyncDirection.syncDirection,
                    bookmarksFileURL: chromeURL
                )
            )
        }

        if let safariClientID = config.safariClientID, let safariURL = config.safariBookmarksURL {
            result.append(
                SyncBrowserConfig(
                    browser: .safari,
                    clientID: safariClientID,
                    direction: config.safariSyncDirection.syncDirection,
                    bookmarksFileURL: safariURL
                )
            )
        }

        return result
    }
}
