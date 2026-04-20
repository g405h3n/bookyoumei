import BookmarkModel
import Foundation
import Store
import SyncEngine

public protocol ResetServicing {
    func reset(config: RuntimeConfig, purgeStore: Bool, confirmedPurge: Bool) throws
}

public final class ResetService: ResetServicing {
    private let storeClient: any BookmarkStoreClient
    private let runtimeController: RuntimeControlling
    private let fileManager: FileManager

    public init(
        storeClient: any BookmarkStoreClient,
        runtimeController: RuntimeControlling,
        fileManager: FileManager = .default
    ) {
        self.storeClient = storeClient
        self.runtimeController = runtimeController
        self.fileManager = fileManager
    }

    public func reset(config: RuntimeConfig, purgeStore: Bool, confirmedPurge: Bool) throws {
        runtimeController.stopIfNeeded()

        let paths = LocalStatePaths(stateDirectoryURL: config.stateDirectoryURL)
        try clearLocalState(paths: paths)
        try markClientsUnavailable(config: config)

        if purgeStore {
            guard confirmedPurge else {
                throw CLIError.purgeDeclined
            }
            try deleteIfExists(at: config.storeFileURL)
            try deleteIfExists(at: config.snapshotsDirectoryURL)
        }
    }

    private func clearLocalState(paths: LocalStatePaths) throws {
        try deleteIfExists(at: paths.pauseFlagURL)
        try deleteIfExists(at: paths.antiChurnURL)
        try deleteIfExists(at: paths.loopHistoryURL)
        try deleteIfExists(at: paths.clientBindingsURL)
        try deleteIfExists(at: paths.logFileURL)
    }

    private func deleteIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func markClientsUnavailable(config: RuntimeConfig) throws {
        // swiftlint:disable trailing_comma
        let targetClientIDs = Set([
            config.chromeClientID,
            config.safariClientID,
        ].compactMap(\.self))
        // swiftlint:enable trailing_comma

        guard !targetClientIDs.isEmpty else {
            return
        }

        var attempts = 0
        while attempts < 2 {
            attempts += 1
            guard let document = try storeClient.load() else {
                return
            }

            let updatedClients = document.metadata.clients.map { client in
                guard targetClientIDs.contains(client.clientID) else { return client }
                return StoreClient(
                    clientID: client.clientID,
                    browser: client.browser,
                    platform: client.platform,
                    profileHint: client.profileHint,
                    status: .unavailable
                )
            }

            if updatedClients == document.metadata.clients {
                return
            }

            do {
                _ = try storeClient.write(
                    items: document.items,
                    writerClientID: config.writerClientID,
                    clients: updatedClients,
                    expectedStoreRevision: document.metadata.storeRevision,
                    now: Date()
                )
                return
            } catch BookmarkStoreError.revisionConflict {
                if attempts >= 2 {
                    throw BookmarkStoreError.revisionConflict(
                        expected: document.metadata.storeRevision,
                        actual: document.metadata.storeRevision + 1
                    )
                }
                continue
            }
        }
    }
}
