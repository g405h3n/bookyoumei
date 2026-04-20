@testable import BookmarkModel
import Foundation
@testable import Store
import Testing

// swiftlint:disable trailing_comma
@Suite("BookmarkStore")
struct BookmarkStoreTests {
    @Test func defaultStoreURLPointsToICloudStoreJSON() {
        let url = BookmarkStore.defaultStoreURL()
        #expect(url.path.hasSuffix("Library/Mobile Documents/com~apple~CloudDocs/bookmarknot/store.json"))
    }

    @Test func loadMissingStoreReturnsNil() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storeURL = tempDir.appendingPathComponent("store.json")
        let store = BookmarkStore(fileURL: storeURL)

        let loaded = try store.load()
        #expect(loaded == nil)
    }

    @Test func writeThenLoadRoundTripPreservesItemsAndMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storeURL = tempDir.appendingPathComponent("store.json")
        let store = BookmarkStore(fileURL: storeURL)

        let client = StoreClient(
            clientID: "chrome-mac-001",
            browser: .chrome,
            platform: .macos,
            profileHint: "Default",
            status: .active
        )

        let rootFolder = BookmarkItem(
            id: "bookmarks_bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar"
        )
        let childBookmark = BookmarkItem(
            id: "bookmark-1",
            type: .bookmark,
            parentID: "bookmarks_bar",
            position: 0,
            title: "Example",
            url: "https://example.com/",
            dateAdded: Date(timeIntervalSince1970: 1_710_000_000),
            dateModified: Date(timeIntervalSince1970: 1_710_000_500),
            identifierMap: ["chrome-mac-001": "guid-1"]
        )
        let inputItems = [rootFolder, childBookmark]

        let written = try store.write(
            items: inputItems,
            writerClientID: "chrome-mac-001",
            clients: [client],
            expectedStoreRevision: nil
        )

        #expect(written.metadata.schemaVersion == 1)
        #expect(written.metadata.storeRevision == 1)
        #expect(written.metadata.writtenByClientID == "chrome-mac-001")
        #expect(written.items == inputItems)

        let loaded = try #require(try store.load())
        #expect(loaded.metadata.schemaVersion == 1)
        #expect(loaded.metadata.storeRevision == 1)
        #expect(loaded.metadata.writtenByClientID == "chrome-mac-001")
        #expect(loaded.items == inputItems)
        #expect(loaded.metadata.clients == [client])
    }

    @Test func writeIncrementsStoreRevision() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storeURL = tempDir.appendingPathComponent("store.json")
        let store = BookmarkStore(fileURL: storeURL)

        let first = try store.write(
            items: [],
            writerClientID: "safari-mac-001",
            clients: [],
            expectedStoreRevision: nil
        )
        #expect(first.metadata.storeRevision == 1)

        let second = try store.write(items: [], writerClientID: "safari-mac-001", clients: [], expectedStoreRevision: 1)
        #expect(second.metadata.storeRevision == 2)
    }

    @Test func writeFailsOnRevisionConflict() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storeURL = tempDir.appendingPathComponent("store.json")
        let store = BookmarkStore(fileURL: storeURL)

        _ = try store.write(items: [], writerClientID: "safari-mac-001", clients: [], expectedStoreRevision: nil)

        #expect(throws: BookmarkStoreError.revisionConflict(expected: 5, actual: 1)) {
            _ = try store.write(items: [], writerClientID: "safari-mac-001", clients: [], expectedStoreRevision: 5)
        }
    }

    @Test func loadRejectsUnsupportedSchemaVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storeURL = tempDir.appendingPathComponent("store.json")
        let store = BookmarkStore(fileURL: storeURL)
        let json = """
        {
          "metadata": {
            "schema_version": 999,
            "store_revision": 1,
            "written_by_client_id": "chrome-mac-001",
            "updated_at": "2026-04-18T00:00:00Z",
            "clients": []
          },
          "items": []
        }
        """
        try json.data(using: .utf8)?.write(to: storeURL, options: .atomic)

        #expect(throws: BookmarkStoreError.unsupportedSchemaVersion(
            expected: BookmarkStore.schemaVersion,
            actual: 999
        )) {
            _ = try store.load()
        }
    }

    // swiftlint:disable:next function_body_length
    @Test func latestSnapshotCanRestoreStorePayloadWithMonotonicRevision() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storeURL = tempDir.appendingPathComponent("store.json")
        let snapshotsURL = tempDir.appendingPathComponent("custom-snapshots")
        let store = BookmarkStore(fileURL: storeURL, snapshotsDirectoryURL: snapshotsURL)

        let seedClients = [
            StoreClient(
                clientID: "chrome-client",
                browser: .chrome,
                platform: .macos,
                profileHint: "Default",
                status: .active
            ),
            StoreClient(
                clientID: "safari-client",
                browser: .safari,
                platform: .macos,
                status: .active
            ),
        ]
        let current = try store.write(
            items: [
                BookmarkItem(
                    id: "bookmarks_bar",
                    type: .folder,
                    parentID: nil,
                    position: 0,
                    title: "Bookmarks Bar"
                ),
            ],
            writerClientID: "writer-current",
            clients: seedClients,
            expectedStoreRevision: nil
        )
        #expect(current.metadata.storeRevision == 1)

        let snapshotDocument = StoreDocument(
            metadata: StoreMetadata(
                schemaVersion: BookmarkStore.schemaVersion,
                storeRevision: 1,
                writtenByClientID: "writer-snapshot",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                clients: [
                    StoreClient(
                        clientID: "chrome-client",
                        browser: .chrome,
                        platform: .macos,
                        profileHint: "Default",
                        status: .unavailable
                    ),
                ]
            ),
            items: [
                BookmarkItem(
                    id: "bookmarks_bar",
                    type: .folder,
                    parentID: nil,
                    position: 0,
                    title: "Bookmarks Bar"
                ),
                BookmarkItem(
                    id: "bookmark-1",
                    type: .bookmark,
                    parentID: "bookmarks_bar",
                    position: 0,
                    title: "Example",
                    url: "https://example.com/",
                    identifierMap: ["chrome-client": "bookmark-1"]
                ),
            ]
        )

        _ = try store.createSnapshot(from: snapshotDocument, now: Date(timeIntervalSince1970: 1_700_000_010))
        let restored = try store.restoreLatestSnapshot(
            writerClientID: "writer-restore",
            now: Date(timeIntervalSince1970: 1_700_000_100)
        )

        #expect(restored.metadata.storeRevision == 2)
        #expect(restored.metadata.writtenByClientID == "writer-restore")
        #expect(restored.items == snapshotDocument.items)
        #expect(restored.metadata.clients == snapshotDocument.metadata.clients)

        let loaded = try #require(try store.load())
        #expect(loaded == restored)
        #expect(FileManager.default.fileExists(atPath: snapshotsURL.path))
    }
}

// swiftlint:enable trailing_comma
