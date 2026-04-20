import Foundation
import Store

public protocol ConfigLoading {
    func load(configPathOverride: String?) throws -> RuntimeConfig
}

public struct ConfigLoader: ConfigLoading {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(configPathOverride: String?) throws -> RuntimeConfig {
        let configPath = configPathOverride ?? defaultConfigPath()
        let configURL = URL(fileURLWithPath: NSString(string: configPath).expandingTildeInPath)
        if !fileManager.fileExists(atPath: configURL.path) {
            throw CLIError.configNotFound(configURL.path)
        }

        let raw = try String(contentsOf: configURL, encoding: .utf8)
        let dictionary = parse(raw)
        let defaultConfig = defaults()

        return try RuntimeConfig(
            writerClientID: dictionary["writer_client_id"] ?? "",
            chromeClientID: dictionary["chrome_client_id"] ?? defaultConfig.chromeClientID,
            safariClientID: dictionary["safari_client_id"] ?? defaultConfig.safariClientID,
            chromeBookmarksURL: resolvedURL(from: dictionary["chrome_bookmarks_path"]) ?? defaultConfig
                .chromeBookmarksURL,
            safariBookmarksURL: resolvedURL(from: dictionary["safari_bookmarks_path"]) ?? defaultConfig
                .safariBookmarksURL,
            chromeSyncDirection: direction(from: dictionary["sync_direction.chrome"]) ?? defaultConfig
                .chromeSyncDirection,
            safariSyncDirection: direction(from: dictionary["sync_direction.safari"]) ?? defaultConfig
                .safariSyncDirection,
            storeFileURL: resolvedURL(from: dictionary["store_path"]) ?? defaultConfig.storeFileURL,
            snapshotsDirectoryURL: resolvedURL(from: dictionary["snapshots_path"]) ?? defaultConfig
                .snapshotsDirectoryURL,
            stateDirectoryURL: resolvedURL(from: dictionary["state_path"]) ?? defaultConfig.stateDirectoryURL,
            sortAfterImport: bool(from: dictionary["sort_after_import"]) ?? defaultConfig.sortAfterImport,
            safeSyncLimit: int(
                from: dictionary["safe_sync_limit"],
                key: "safe_sync_limit"
            ) ?? defaultConfig.safeSyncLimit,
            logFileURL: resolvedURL(from: dictionary["log_path"]) ?? defaultConfig.logFileURL
        )
    }

    private func defaults() -> RuntimeConfig {
        let home = fileManager.homeDirectoryForCurrentUser
        let storeFileURL = BookmarkStore.defaultStoreURL()
        let snapshotsDirectoryURL = storeFileURL.deletingLastPathComponent().appendingPathComponent("snapshots")
        let stateDirectoryURL = home
            .appendingPathComponent(".local")
            .appendingPathComponent("state")
            .appendingPathComponent("bookmarknot")

        return RuntimeConfig(
            writerClientID: "",
            chromeClientID: nil,
            safariClientID: nil,
            chromeBookmarksURL: home
                .appendingPathComponent("Library/Application Support/Google/Chrome")
                .appendingPathComponent("Default")
                .appendingPathComponent("Bookmarks"),
            safariBookmarksURL: home
                .appendingPathComponent("Library/Safari")
                .appendingPathComponent("Bookmarks.plist"),
            chromeSyncDirection: .both,
            safariSyncDirection: .both,
            storeFileURL: storeFileURL,
            snapshotsDirectoryURL: snapshotsDirectoryURL,
            stateDirectoryURL: stateDirectoryURL,
            sortAfterImport: false,
            safeSyncLimit: 100,
            logFileURL: stateDirectoryURL.appendingPathComponent("events.log")
        )
    }

    private func parse(_ raw: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in raw.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let valueStart = trimmed.index(after: colonIndex)
            let value = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespaces)
            values[key] = value
        }
        return values
    }

    private func resolvedURL(from path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }

    private func direction(from value: String?) -> DirectionSetting? {
        guard let value else { return nil }
        return DirectionSetting(rawValue: value)
    }

    private func bool(from value: String?) -> Bool? {
        guard let value else { return nil }
        switch value.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private func int(from value: String?, key: String) throws -> Int? {
        guard let value else { return nil }
        guard let parsed = Int(value) else {
            throw CLIError.invalidArguments("invalid \(key): \(value)")
        }
        return parsed
    }

    private func defaultConfigPath() -> String {
        "~/.config/bookmarknot/config.yaml"
    }
}
