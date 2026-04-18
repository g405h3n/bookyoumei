import BookmarkModel
import Foundation

public struct BookmarkStore {
    public static let schemaVersion = 1

    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = Self.defaultStoreURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
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
}

public enum BookmarkStoreError: Error, Equatable {
    case revisionConflict(expected: Int, actual: Int)
    case unsupportedSchemaVersion(expected: Int, actual: Int)
}
