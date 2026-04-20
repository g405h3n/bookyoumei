import BookmarkModel
@testable import CLIApp
import Foundation
import Store
import SyncEngine
import Testing

// swiftlint:disable trailing_comma
@Suite("UndoService")
struct UndoServiceTests {
    // swiftlint:disable:next function_body_length
    @Test func undoRestoresLatestSnapshotAndExportsToEnabledBrowsers() throws {
        let snapshotItems = [
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
                url: "https://example.com",
                identifierMap: ["chrome-client": "bookmark-1", "safari-client": "bookmark-1"]
            ),
        ]

        let storeClient = StubStoreClient(
            document: StoreDocument(
                metadata: StoreMetadata(
                    schemaVersion: BookmarkStore.schemaVersion,
                    storeRevision: 10,
                    writtenByClientID: "seed",
                    updatedAt: Date(timeIntervalSince1970: 1),
                    clients: []
                ),
                items: []
            )
        )
        storeClient.snapshots = [
            StoreDocument(
                metadata: StoreMetadata(
                    schemaVersion: BookmarkStore.schemaVersion,
                    storeRevision: 9,
                    writtenByClientID: "seed",
                    updatedAt: Date(timeIntervalSince1970: 1),
                    clients: []
                ),
                items: snapshotItems
            ),
        ]

        let chromeAdapter = RecordingBrowserSyncAdapter()
        let safariAdapter = RecordingBrowserSyncAdapter()
        let service = UndoService(
            storeClient: storeClient,
            adapters: [
                .chrome: chromeAdapter,
                .safari: safariAdapter,
            ]
        )

        let config = RuntimeConfig.fixture(
            chromeSyncDirection: .exportOnly,
            safariSyncDirection: .both
        )
        let result = try service.undo(config: config)

        #expect(result.exportedBrowsers == [.chrome, .safari])
        #expect(result.restoredRevision == 11)
        #expect(chromeAdapter.lastWrittenItems == snapshotItems)
        #expect(safariAdapter.lastWrittenItems == snapshotItems)
    }

    @Test func undoFailsWhenNoSnapshotsExist() throws {
        let service = UndoService(
            storeClient: StubStoreClient(document: nil),
            adapters: [.chrome: RecordingBrowserSyncAdapter()]
        )

        #expect(throws: BookmarkStoreError.snapshotNotFound) {
            _ = try service.undo(config: RuntimeConfig.fixture())
        }
    }

    @Test func undoSucceedsWhenNoExportBrowsersAreConfigured() throws {
        let storeClient = StubStoreClient(
            document: StoreDocument(
                metadata: StoreMetadata(
                    schemaVersion: BookmarkStore.schemaVersion,
                    storeRevision: 3,
                    writtenByClientID: "seed",
                    updatedAt: Date(timeIntervalSince1970: 1),
                    clients: []
                ),
                items: []
            )
        )
        storeClient.snapshots = [
            StoreDocument(
                metadata: StoreMetadata(
                    schemaVersion: BookmarkStore.schemaVersion,
                    storeRevision: 2,
                    writtenByClientID: "seed",
                    updatedAt: Date(timeIntervalSince1970: 1),
                    clients: []
                ),
                items: []
            ),
        ]

        let chromeAdapter = RecordingBrowserSyncAdapter()
        let service = UndoService(
            storeClient: storeClient,
            adapters: [.chrome: chromeAdapter]
        )
        let config = RuntimeConfig.fixture(
            chromeSyncDirection: .importOnly,
            safariSyncDirection: .importOnly
        )

        let result = try service.undo(config: config)
        #expect(result.exportedBrowsers.isEmpty)
        #expect(result.restoredRevision == 4)
        #expect(chromeAdapter.lastWrittenItems == nil)
    }
}

// swiftlint:enable trailing_comma

private final class RecordingBrowserSyncAdapter: BrowserSyncAdapter {
    var lastWrittenItems: [BookmarkItem]?

    func read(config _: SyncBrowserConfig) throws -> [BookmarkItem] {
        []
    }

    func write(items: [BookmarkItem], config _: SyncBrowserConfig) throws {
        lastWrittenItems = items
    }
}
