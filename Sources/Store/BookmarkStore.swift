import BookmarkModel
import Foundation

public struct BookmarkStore {
    public static let schemaVersion = 1

    public let fileURL: URL
    public let snapshotsDirectoryURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL = Self.defaultStoreURL(),
        snapshotsDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.snapshotsDirectoryURL = snapshotsDirectoryURL
            ?? fileURL.deletingLastPathComponent().appendingPathComponent("snapshots")
        self.fileManager = fileManager
    }

    public static func defaultStoreURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/bookmarknot")
            .appendingPathComponent("store.json")
    }

    public func load() throws -> StoreDocument? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(StoreDocument.self, from: data)

        guard document.metadata.schemaVersion == Self.schemaVersion else {
            throw BookmarkStoreError.unsupportedSchemaVersion(
                expected: Self.schemaVersion,
                actual: document.metadata.schemaVersion
            )
        }

        return document
    }

    public func write(
        items: [BookmarkItem],
        writerClientID: String,
        clients: [StoreClient],
        expectedStoreRevision: Int?,
        now: Date = Date()
    ) throws -> StoreDocument {
        let current = try load()
        let currentRevision = current?.metadata.storeRevision ?? 0

        if let expectedStoreRevision, expectedStoreRevision != currentRevision {
            throw BookmarkStoreError.revisionConflict(expected: expectedStoreRevision, actual: currentRevision)
        }

        let document = StoreDocument(
            metadata: StoreMetadata(
                schemaVersion: Self.schemaVersion,
                storeRevision: currentRevision + 1,
                writtenByClientID: writerClientID,
                updatedAt: now,
                clients: clients
            ),
            items: items
        )

        try writeToDisk(document)
        return document
    }

    private func writeToDisk(_ document: StoreDocument) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func createSnapshot(from document: StoreDocument, now: Date = Date()) throws -> URL {
        try fileManager.createDirectory(at: snapshotsDirectoryURL, withIntermediateDirectories: true)
        let snapshotURL = snapshotsDirectoryURL.appendingPathComponent(snapshotFileName(now: now, revision: document
                .metadata.storeRevision))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: snapshotURL, options: .atomic)
        return snapshotURL
    }

    public func removeSnapshot(at snapshotURL: URL) throws {
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            return
        }
        try fileManager.removeItem(at: snapshotURL)
    }

    public func loadLatestSnapshot() throws -> StoreDocument? {
        guard fileManager.fileExists(atPath: snapshotsDirectoryURL.path) else {
            return nil
        }

        let fileNames = try fileManager.contentsOfDirectory(atPath: snapshotsDirectoryURL.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        guard let latestFileName = fileNames.last else {
            return nil
        }

        let snapshotURL = snapshotsDirectoryURL.appendingPathComponent(latestFileName)
        let data = try Data(contentsOf: snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoreDocument.self, from: data)
    }

    public func restoreLatestSnapshot(
        writerClientID: String,
        now: Date = Date()
    ) throws -> StoreDocument {
        guard let snapshot = try loadLatestSnapshot() else {
            throw BookmarkStoreError.snapshotNotFound
        }

        let expectedRevision = try load()?.metadata.storeRevision
        return try write(
            items: snapshot.items,
            writerClientID: writerClientID,
            clients: snapshot.metadata.clients,
            expectedStoreRevision: expectedRevision,
            now: now
        )
    }

    private func snapshotFileName(now: Date, revision: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
        let timestamp = formatter.string(from: now)
        return "snapshot-\(timestamp)-r\(String(format: "%09d", revision)).json"
    }
}

public enum BookmarkStoreError: Error, Equatable {
    case revisionConflict(expected: Int, actual: Int)
    case unsupportedSchemaVersion(expected: Int, actual: Int)
    case snapshotNotFound
}

extension BookmarkStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .revisionConflict(expected, actual):
            "store revision conflict: expected=\(expected) actual=\(actual)"
        case let .unsupportedSchemaVersion(expected, actual):
            "unsupported schema version: expected=\(expected) actual=\(actual)"
        case .snapshotNotFound:
            "no snapshots available for undo"
        }
    }
}
