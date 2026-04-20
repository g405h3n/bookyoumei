import BookmarkModel
@testable import CLIApp
import Foundation
import Store
import SyncEngine

final class StubConfigLoader: ConfigLoading {
    var config = RuntimeConfig.fixture()
    var loadCallCount = 0
    var lastConfigPathOverride: String?
    var loadError: Error?

    func load(configPathOverride: String?) throws -> RuntimeConfig {
        loadCallCount += 1
        lastConfigPathOverride = configPathOverride
        if let loadError {
            throw loadError
        }
        return config
    }
}

final class StubSyncService: SyncServicing {
    var runSyncCallCount = 0
    var runSyncError: Error?

    func runSync(config: RuntimeConfig) throws -> SyncCycleResult {
        runSyncCallCount += 1
        if let runSyncError {
            throw runSyncError
        }

        return SyncCycleResult(
            didWriteStore: true,
            storeRevision: 1,
            importedBrowsers: [.chrome],
            exportedBrowsers: [.safari],
            skippedByAntiChurn: []
        )
    }
}

final class StubDaemonControl: DaemonControlling {
    var pauseCallCount = 0
    var resumeCallCount = 0

    func pause() throws {
        pauseCallCount += 1
    }

    func resume() throws {
        resumeCallCount += 1
    }
}

final class StubDaemonControlBuilder: DaemonControlBuilding {
    private var byPath: [String: StubDaemonControl] = [:]

    func make(config: RuntimeConfig) -> any DaemonControlling {
        let key = config.stateDirectoryURL.path
        if let existing = byPath[key] {
            return existing
        }
        let created = StubDaemonControl()
        byPath[key] = created
        return created
    }

    func daemonControl(forStatePath path: String) -> StubDaemonControl? {
        byPath[path]
    }
}

final class StubResetService: ResetServicing {
    var resetCallCount = 0

    func reset(config: RuntimeConfig, purgeStore: Bool, confirmedPurge: Bool) throws {
        resetCallCount += 1
    }
}

final class StubResetServiceBuilder: ResetServiceBuilding {
    private let service = StubResetService()

    func make(config _: RuntimeConfig) -> any ResetServicing {
        service
    }

    var builtService: StubResetService {
        service
    }
}

final class StubLogStore: LogStoring {
    var entries: [LogEntry] = []
    var readEntriesCallCount = 0

    func append(level: String, message: String, now: Date) throws {}

    func readEntries() throws -> [LogEntry] {
        readEntriesCallCount += 1
        return entries
    }
}

final class StubLogStoreBuilder: LogStoreBuilding {
    private var byPath: [String: StubLogStore] = [:]

    func make(config: RuntimeConfig) -> any LogStoring {
        let key = config.logFileURL.path
        if let existing = byPath[key] {
            return existing
        }
        let created = StubLogStore()
        byPath[key] = created
        return created
    }

    func logStore(forLogPath path: String) -> StubLogStore? {
        byPath[path]
    }
}

final class TestIO: CLIIO {
    var stdout: [String] = []
    var stderr: [String] = []
    var stdinQueue: [String] = []

    func writeOut(_ line: String) {
        stdout.append(line)
    }

    func writeErr(_ line: String) {
        stderr.append(line)
    }

    func readLine() -> String? {
        guard !stdinQueue.isEmpty else {
            return nil
        }
        return stdinQueue.removeFirst()
    }
}

final class StubRuntimeController: RuntimeControlling {
    var startCallCount = 0
    var stopCallCount = 0

    func startIfNeeded() {
        startCallCount += 1
    }

    func stopIfNeeded() {
        stopCallCount += 1
    }
}

final class StubStoreClient: BookmarkStoreClient {
    var document: StoreDocument?
    var writeCallCount = 0
    var lastWrittenClients: [StoreClient]?
    var lastExpectedStoreRevision: Int?
    var simulateRevisionConflictOnFirstWrite = false

    init(document: StoreDocument?) {
        self.document = document
    }

    func load() throws -> StoreDocument? {
        document
    }

    func write(
        items: [BookmarkItem],
        writerClientID: String,
        clients: [StoreClient],
        expectedStoreRevision: Int?,
        now: Date
    ) throws -> StoreDocument {
        writeCallCount += 1
        lastWrittenClients = clients
        lastExpectedStoreRevision = expectedStoreRevision

        if simulateRevisionConflictOnFirstWrite, writeCallCount == 1 {
            let existingClients = document?.metadata.clients ?? clients
            let nextRevision = (document?.metadata.storeRevision ?? 0) + 1
            document = StoreDocument(
                metadata: StoreMetadata(
                    schemaVersion: BookmarkStore.schemaVersion,
                    storeRevision: nextRevision,
                    writtenByClientID: "other",
                    updatedAt: now,
                    clients: existingClients
                ),
                items: items
            )
            throw BookmarkStoreError.revisionConflict(
                expected: expectedStoreRevision ?? 0,
                actual: nextRevision
            )
        }

        let next = StoreDocument(
            metadata: StoreMetadata(
                schemaVersion: BookmarkStore.schemaVersion,
                storeRevision: (document?.metadata.storeRevision ?? 0) + 1,
                writtenByClientID: writerClientID,
                updatedAt: now,
                clients: clients
            ),
            items: items
        )
        document = next
        return next
    }
}

func withTemporaryDirectory(_ operation: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bookmarknot-cli-tests")
        .appendingPathComponent(UUID().uuidString)

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    try operation(directory)
}

func seedLocalState(paths: LocalStatePaths) throws {
    let manager = FileManager.default
    try manager.createDirectory(at: paths.stateDirectoryURL, withIntermediateDirectories: true)
    try Data("pause".utf8).write(to: paths.pauseFlagURL)
    try Data("anti".utf8).write(to: paths.antiChurnURL)
    try Data("loop".utf8).write(to: paths.loopHistoryURL)
    try Data("bindings".utf8).write(to: paths.clientBindingsURL)
    try Data("logs".utf8).write(to: paths.logFileURL)
}

extension RuntimeConfig {
    static func fixture(
        writerClientID: String = "writer-client",
        chromeClientID: String? = "chrome-client",
        safariClientID: String? = "safari-client",
        chromeBookmarksURL: URL? = URL(fileURLWithPath: "/tmp/chrome-bookmarks"),
        safariBookmarksURL: URL? = URL(fileURLWithPath: "/tmp/safari-bookmarks"),
        chromeSyncDirection: DirectionSetting = .both,
        safariSyncDirection: DirectionSetting = .both,
        storeFileURL: URL = URL(fileURLWithPath: "/tmp/store.json"),
        snapshotsDirectoryURL: URL = URL(fileURLWithPath: "/tmp/snapshots"),
        stateDirectoryURL: URL = URL(fileURLWithPath: "/tmp/bookmarknot-state"),
        sortAfterImport: Bool = false,
        safeSyncLimit: Int = 100,
        logFileURL: URL = URL(fileURLWithPath: "/tmp/bookmarknot-state/events.log")
    ) -> RuntimeConfig {
        RuntimeConfig(
            writerClientID: writerClientID,
            chromeClientID: chromeClientID,
            safariClientID: safariClientID,
            chromeBookmarksURL: chromeBookmarksURL,
            safariBookmarksURL: safariBookmarksURL,
            chromeSyncDirection: chromeSyncDirection,
            safariSyncDirection: safariSyncDirection,
            storeFileURL: storeFileURL,
            snapshotsDirectoryURL: snapshotsDirectoryURL,
            stateDirectoryURL: stateDirectoryURL,
            sortAfterImport: sortAfterImport,
            safeSyncLimit: safeSyncLimit,
            logFileURL: logFileURL
        )
    }

    static func missingForSync() -> RuntimeConfig {
        fixture(
            chromeClientID: nil,
            chromeBookmarksURL: nil
        )
    }
}
