import Foundation
import SyncEngine

// swiftlint:disable opening_brace
enum BrowserSyncRuntimeFactory {
    static func makeAdapters() -> [SyncBrowser: any BrowserSyncAdapter] {
        // swiftlint:disable trailing_comma
        [
            .chrome: ChromeSyncAdapter(),
            .safari: SafariSyncAdapter(),
        ]
        // swiftlint:enable trailing_comma
    }

    static func buildSyncBrowserConfigs(config: RuntimeConfig) -> [SyncBrowserConfig] {
        buildBrowserConfigs(config: config, includeDirection: { _ in true })
    }

    static func buildExportBrowserConfigs(config: RuntimeConfig) -> [SyncBrowserConfig] {
        buildBrowserConfigs(config: config, includeDirection: {
            $0 == .both || $0 == .exportOnly
        })
    }

    private static func buildBrowserConfigs(
        config: RuntimeConfig,
        includeDirection: (DirectionSetting) -> Bool
    ) -> [SyncBrowserConfig] {
        var result: [SyncBrowserConfig] = []

        if includeDirection(config.chromeSyncDirection),
           let chromeClientID = config.chromeClientID,
           let chromeURL = config.chromeBookmarksURL
        {
            result.append(
                SyncBrowserConfig(
                    browser: .chrome,
                    clientID: chromeClientID,
                    direction: config.chromeSyncDirection.syncDirection,
                    bookmarksFileURL: chromeURL
                )
            )
        }

        if includeDirection(config.safariSyncDirection),
           let safariClientID = config.safariClientID,
           let safariURL = config.safariBookmarksURL
        {
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

// swiftlint:enable opening_brace
