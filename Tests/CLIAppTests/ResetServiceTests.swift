@testable import CLIApp
import Foundation
import Store
import Testing

@Suite("ResetService")
struct ResetServiceTests {
    @Test func resetDefaultClearsLocalStateAndMarksClientsUnavailable() throws {
        try withTemporaryDirectory { directory in
            let local = LocalStatePaths(stateDirectoryURL: directory)
            try seedLocalState(paths: local)

            let storeURL = directory.appendingPathComponent("store.json")
            let snapshotsURL = directory.appendingPathComponent("snapshots")
            try Data("{}\n".utf8).write(to: storeURL)
            try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
            try Data("snapshot".utf8).write(to: snapshotsURL.appendingPathComponent("s1.json"))

            let storeClient = StubStoreClient(
                document: makeStoreDocument(revision: 1, statuses: [.active, .active])
            )
            let runtime = StubRuntimeController()
            let resetService = ResetService(
                storeClient: storeClient,
                runtimeController: runtime,
                fileManager: .default
            )

            let config = RuntimeConfig(
                writerClientID: "writer",
                chromeClientID: "chrome-client",
                safariClientID: "safari-client",
                chromeBookmarksURL: nil,
                safariBookmarksURL: nil,
                chromeSyncDirection: .both,
                safariSyncDirection: .both,
                storeFileURL: storeURL,
                snapshotsDirectoryURL: snapshotsURL,
                stateDirectoryURL: directory,
                sortAfterImport: false,
                safeSyncLimit: 100,
                logFileURL: local.logFileURL
            )

            try resetService.reset(config: config, purgeStore: false, confirmedPurge: false)

            #expect(runtime.stopCallCount == 1)
            #expect(storeClient.writeCallCount == 1)
            #expect(storeClient.lastWrittenClients?.allSatisfy { $0.status == .unavailable } == true)
            #expect(!FileManager.default.fileExists(atPath: local.pauseFlagURL.path))
            #expect(!FileManager.default.fileExists(atPath: local.logFileURL.path))
            #expect(!FileManager.default.fileExists(atPath: local.antiChurnURL.path))
            #expect(!FileManager.default.fileExists(atPath: local.clientBindingsURL.path))
            #expect(!FileManager.default.fileExists(atPath: local.loopHistoryURL.path))
            #expect(FileManager.default.fileExists(atPath: storeURL.path))
            #expect(FileManager.default.fileExists(atPath: snapshotsURL.path))
        }
    }

    @Test func resetPurgeDeclinedConfirmationDoesNotDeleteStore() throws {
        try withTemporaryDirectory { directory in
            let storeURL = directory.appendingPathComponent("store.json")
            let snapshotsURL = directory.appendingPathComponent("snapshots")
            try Data("{}".utf8).write(to: storeURL)
            try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)

            let resetService = ResetService(
                storeClient: StubStoreClient(document: nil),
                runtimeController: StubRuntimeController(),
                fileManager: .default
            )

            let config = RuntimeConfig(
                writerClientID: "writer",
                chromeClientID: nil,
                safariClientID: nil,
                chromeBookmarksURL: nil,
                safariBookmarksURL: nil,
                chromeSyncDirection: .both,
                safariSyncDirection: .both,
                storeFileURL: storeURL,
                snapshotsDirectoryURL: snapshotsURL,
                stateDirectoryURL: directory,
                sortAfterImport: false,
                safeSyncLimit: 100,
                logFileURL: directory.appendingPathComponent("events.log")
            )

            #expect(throws: CLIError.self) {
                try resetService.reset(config: config, purgeStore: true, confirmedPurge: false)
            }

            #expect(FileManager.default.fileExists(atPath: storeURL.path))
            #expect(FileManager.default.fileExists(atPath: snapshotsURL.path))
        }
    }

    @Test func resetPurgeDeletesSharedStoreAfterConfirmation() throws {
        try withTemporaryDirectory { directory in
            let storeURL = directory.appendingPathComponent("store.json")
            let snapshotsURL = directory.appendingPathComponent("snapshots")
            try Data("{}".utf8).write(to: storeURL)
            try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)

            let resetService = ResetService(
                storeClient: StubStoreClient(document: nil),
                runtimeController: StubRuntimeController(),
                fileManager: .default
            )

            let config = RuntimeConfig(
                writerClientID: "writer",
                chromeClientID: nil,
                safariClientID: nil,
                chromeBookmarksURL: nil,
                safariBookmarksURL: nil,
                chromeSyncDirection: .both,
                safariSyncDirection: .both,
                storeFileURL: storeURL,
                snapshotsDirectoryURL: snapshotsURL,
                stateDirectoryURL: directory,
                sortAfterImport: false,
                safeSyncLimit: 100,
                logFileURL: directory.appendingPathComponent("events.log")
            )

            try resetService.reset(config: config, purgeStore: true, confirmedPurge: true)

            #expect(!FileManager.default.fileExists(atPath: storeURL.path))
            #expect(!FileManager.default.fileExists(atPath: snapshotsURL.path))
        }
    }

    @Test func resetUnavailableMarkRetriesOnRevisionConflictOnce() throws {
        let storeClient = StubStoreClient(document: makeStoreDocument(revision: 3, statuses: [.active]))
        storeClient.simulateRevisionConflictOnFirstWrite = true

        let resetService = ResetService(
            storeClient: storeClient,
            runtimeController: StubRuntimeController(),
            fileManager: .default
        )

        let directory = FileManager.default.temporaryDirectory
        let config = RuntimeConfig(
            writerClientID: "writer",
            chromeClientID: "chrome-client",
            safariClientID: nil,
            chromeBookmarksURL: nil,
            safariBookmarksURL: nil,
            chromeSyncDirection: .both,
            safariSyncDirection: .both,
            storeFileURL: directory.appendingPathComponent("unused-store.json"),
            snapshotsDirectoryURL: directory.appendingPathComponent("unused-snapshots"),
            stateDirectoryURL: directory,
            sortAfterImport: false,
            safeSyncLimit: 100,
            logFileURL: directory.appendingPathComponent("unused.log")
        )

        try resetService.reset(config: config, purgeStore: false, confirmedPurge: false)

        #expect(storeClient.writeCallCount == 2)
        #expect(storeClient.lastExpectedStoreRevision == 4)
    }
}

private func makeStoreDocument(revision: Int, statuses: [StoreClientStatus]) -> StoreDocument {
    let clients = statuses.enumerated().map { index, status in
        StoreClient(
            clientID: index == 0 ? "chrome-client" : "safari-client",
            browser: index == 0 ? .chrome : .safari,
            platform: .macos,
            status: status
        )
    }

    return StoreDocument(
        metadata: StoreMetadata(
            schemaVersion: BookmarkStore.schemaVersion,
            storeRevision: revision,
            writtenByClientID: "writer",
            updatedAt: Date(timeIntervalSince1970: 1),
            clients: clients
        ),
        items: []
    )
}
