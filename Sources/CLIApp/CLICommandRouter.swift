import Foundation
import Store
import SyncEngine

public protocol CLIIO {
    func writeOut(_ line: String)
    func writeErr(_ line: String)
    func readLine() -> String?
}

public struct ConsoleIO: CLIIO {
    public init() {}

    public func writeOut(_ line: String) {
        print(line)
    }

    public func writeErr(_ line: String) {
        fputs("\(line)\n", stderr)
    }

    public func readLine() -> String? {
        Swift.readLine()
    }
}

public final class CLICommandRouter {
    private let configLoader: any ConfigLoading
    private let syncService: any SyncServicing
    private let daemonControlBuilder: any DaemonControlBuilding
    private let resetServiceBuilder: any ResetServiceBuilding
    private let logStoreBuilder: any LogStoreBuilding

    public init(
        configLoader: any ConfigLoading,
        syncService: any SyncServicing,
        daemonControlBuilder: any DaemonControlBuilding,
        resetServiceBuilder: any ResetServiceBuilding,
        logStoreBuilder: any LogStoreBuilding
    ) {
        self.configLoader = configLoader
        self.syncService = syncService
        self.daemonControlBuilder = daemonControlBuilder
        self.resetServiceBuilder = resetServiceBuilder
        self.logStoreBuilder = logStoreBuilder
    }

    public static func live() -> CLICommandRouter {
        let loader = ConfigLoader()
        return CLICommandRouter(
            configLoader: loader,
            syncService: SyncService(),
            daemonControlBuilder: LiveDaemonControlBuilder(),
            resetServiceBuilder: LiveResetServiceBuilder(),
            logStoreBuilder: LiveLogStoreBuilder()
        )
    }

    public func execute(arguments: [String], io terminalIO: CLIIO) -> Int {
        do {
            let parsed = try parse(arguments)
            let config = try configLoader.load(configPathOverride: parsed.configPath)

            switch parsed.command {
            case "sync":
                return try handleSync(config: config, io: terminalIO)
            case "pause":
                return try handlePause(config: config, io: terminalIO)
            case "resume":
                return try handleResume(config: config, io: terminalIO)
            case "reset":
                return try handleReset(parsed: parsed, config: config, io: terminalIO)
            case "logs":
                return try handleLogs(config: config, io: terminalIO)
            default:
                terminalIO.writeErr(usage())
                return 2
            }
        } catch {
            terminalIO.writeErr(error.localizedDescription)
            if case .invalidArguments = error as? CLIError {
                terminalIO.writeErr(usage())
                return 2
            }
            return 1
        }
    }

    private func handleSync(config: RuntimeConfig, io terminalIO: CLIIO) throws -> Int {
        try config.validateForSync()
        let result = try syncService.runSync(config: config)
        terminalIO.writeOut(summary(for: result))
        return 0
    }

    private func handlePause(config: RuntimeConfig, io terminalIO: CLIIO) throws -> Int {
        let daemonControl = daemonControlBuilder.make(config: config)
        try daemonControl.pause()
        terminalIO.writeOut("sync paused")
        return 0
    }

    private func handleResume(config: RuntimeConfig, io terminalIO: CLIIO) throws -> Int {
        let daemonControl = daemonControlBuilder.make(config: config)
        try daemonControl.resume()
        terminalIO.writeOut("sync resumed")
        return 0
    }

    private func handleReset(parsed: ParsedArguments, config: RuntimeConfig, io terminalIO: CLIIO) throws -> Int {
        try config.validateForReset()
        let resetService = resetServiceBuilder.make(config: config)
        let confirmed = try resolveResetConfirmation(
            purgeStore: parsed.purgeStore,
            forceYes: parsed.forceYes,
            io: terminalIO
        )
        try resetService.reset(config: config, purgeStore: parsed.purgeStore, confirmedPurge: confirmed)
        terminalIO.writeOut("reset completed")
        return 0
    }

    private func handleLogs(config: RuntimeConfig, io terminalIO: CLIIO) throws -> Int {
        let logStore = logStoreBuilder.make(config: config)
        let entries = try logStore.readEntries()
        if entries.isEmpty {
            terminalIO.writeOut("no logs yet")
            return 0
        }

        for entry in entries {
            terminalIO.writeOut("\(entry.timestamp.ISO8601Format()) \(entry.level) \(entry.message)")
        }
        return 0
    }

    private func summary(for result: SyncCycleResult) -> String {
        let revision = result.storeRevision.map(String.init) ?? "nil"
        let importedCount = result.importedBrowsers.count
        let exportedCount = result.exportedBrowsers.count
        return "sync complete: wrote_store=\(result.didWriteStore) revision=\(revision) " +
            "import=\(importedCount) export=\(exportedCount)"
    }

    private func resolveResetConfirmation(purgeStore: Bool, forceYes: Bool, io terminalIO: CLIIO) throws -> Bool {
        guard purgeStore else {
            return false
        }
        if forceYes {
            return true
        }

        terminalIO.writeOut("This will delete the shared bookmark store used by all devices. Continue? [y/N]")
        let input = (terminalIO.readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if input == "y" || input == "yes" {
            return true
        }
        throw CLIError.purgeDeclined
    }

    private func parse(_ arguments: [String]) throws -> ParsedArguments {
        var command: String?
        var configPath: String?
        var purgeStore = false
        var forceYes = false

        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            if token == "--config" {
                let nextIndex = index + 1
                guard nextIndex < arguments.count else {
                    throw CLIError.invalidArguments("--config requires a path")
                }
                configPath = arguments[nextIndex]
                index += 2
                continue
            }

            if command == nil {
                command = token
                index += 1
                continue
            }

            if command == "reset" {
                if token == "--purge-store" {
                    purgeStore = true
                    index += 1
                    continue
                }
                if token == "--yes" {
                    forceYes = true
                    index += 1
                    continue
                }
            }

            throw CLIError.invalidArguments("unknown argument: \(token)")
        }

        guard let command else {
            throw CLIError.invalidArguments(usage())
        }

        return ParsedArguments(
            command: command,
            configPath: configPath,
            purgeStore: purgeStore,
            forceYes: forceYes
        )
    }

    private func usage() -> String {
        "usage: bookmarknot <sync|pause|resume|reset|logs> [--config PATH]"
    }
}

private struct ParsedArguments {
    let command: String
    let configPath: String?
    let purgeStore: Bool
    let forceYes: Bool
}

public protocol DaemonControlBuilding {
    func make(config: RuntimeConfig) -> any DaemonControlling
}

public protocol ResetServiceBuilding {
    func make(config: RuntimeConfig) -> any ResetServicing
}

public protocol LogStoreBuilding {
    func make(config: RuntimeConfig) -> any LogStoring
}

public struct LiveDaemonControlBuilder: DaemonControlBuilding {
    public init() {}

    public func make(config: RuntimeConfig) -> any DaemonControlling {
        DaemonControl(
            stateDirectoryURL: config.stateDirectoryURL,
            runtimeController: NoopRuntimeController()
        )
    }
}

public struct LiveResetServiceBuilder: ResetServiceBuilding {
    public init() {}

    public func make(config: RuntimeConfig) -> any ResetServicing {
        ResetService(
            storeClient: BookmarkStore(fileURL: config.storeFileURL),
            runtimeController: NoopRuntimeController()
        )
    }
}

public struct LiveLogStoreBuilder: LogStoreBuilding {
    public init() {}

    public func make(config: RuntimeConfig) -> any LogStoring {
        LogStore(fileURL: config.logFileURL)
    }
}
