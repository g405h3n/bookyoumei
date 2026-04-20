import Foundation

public protocol RuntimeControlling {
    func startIfNeeded()
    func stopIfNeeded()
}

public struct NoopRuntimeController: RuntimeControlling {
    public init() {}

    public func startIfNeeded() {}

    public func stopIfNeeded() {}
}

public struct LocalStatePaths {
    public let stateDirectoryURL: URL
    public let pauseFlagURL: URL
    public let antiChurnURL: URL
    public let loopHistoryURL: URL
    public let clientBindingsURL: URL
    public let logFileURL: URL

    public init(stateDirectoryURL: URL) {
        self.stateDirectoryURL = stateDirectoryURL
        pauseFlagURL = stateDirectoryURL.appendingPathComponent("paused.flag")
        antiChurnURL = stateDirectoryURL.appendingPathComponent("anti-churn.json")
        loopHistoryURL = stateDirectoryURL.appendingPathComponent("loop-history.json")
        clientBindingsURL = stateDirectoryURL.appendingPathComponent("client-bindings.json")
        logFileURL = stateDirectoryURL.appendingPathComponent("events.log")
    }
}

public protocol DaemonControlling {
    func pause() throws
    func resume() throws
}

public final class DaemonControl: DaemonControlling {
    public var pauseFlagURL: URL {
        paths.pauseFlagURL
    }

    private let paths: LocalStatePaths
    private let runtimeController: RuntimeControlling
    private let fileManager: FileManager

    public init(
        stateDirectoryURL: URL,
        runtimeController: RuntimeControlling,
        fileManager: FileManager = .default
    ) {
        paths = LocalStatePaths(stateDirectoryURL: stateDirectoryURL)
        self.runtimeController = runtimeController
        self.fileManager = fileManager
    }

    public func pause() throws {
        try fileManager.createDirectory(at: paths.stateDirectoryURL, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: paths.pauseFlagURL.path) else {
            return
        }

        runtimeController.stopIfNeeded()
        try Data("paused".utf8).write(to: paths.pauseFlagURL, options: .atomic)
    }

    public func resume() throws {
        guard fileManager.fileExists(atPath: paths.pauseFlagURL.path) else {
            return
        }

        try fileManager.removeItem(at: paths.pauseFlagURL)
        runtimeController.startIfNeeded()
    }
}
