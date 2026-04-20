@testable import BookmarkModel
import Foundation
@testable import Store
@testable import SyncEngine
import Testing

// swiftlint:disable file_length
// swiftlint:disable type_body_length function_body_length trailing_comma
@Suite("SyncCoordinator")
struct SyncCoordinatorTests {
    @Test func importsChromeAndExportsToSafari() throws {
        let chromeClient = "chrome-client"
        let safariClient = "safari-client"

        let chromeItems = browserItems(
            clientID: chromeClient,
            barTitle: "Bookmarks Bar",
            bookmarkID: "chrome-bookmark-1",
            bookmarkTitle: "Example",
            bookmarkURL: "https://example.com"
        )
        let safariItems = browserItems(
            clientID: safariClient,
            barTitle: "Favorites Bar",
            bookmarkID: nil,
            bookmarkTitle: nil,
            bookmarkURL: nil
        )

        let store = InMemoryStore(document: nil)
        let antiChurn = InMemoryAntiChurnStateStore()
        let chromeAdapter = MockBrowserSyncAdapter(itemsToRead: chromeItems)
        let safariAdapter = MockBrowserSyncAdapter(itemsToRead: safariItems)

        let coordinator = SyncCoordinator(
            store: store,
            adapters: [
                .chrome: chromeAdapter,
                .safari: safariAdapter,
            ],
            antiChurnStateStore: antiChurn
        )

        let request = SyncCycleRequest(
            writerClientID: "sync-mac-1",
            browsers: [
                SyncBrowserConfig(
                    browser: .chrome,
                    clientID: chromeClient,
                    direction: .both,
                    bookmarksFileURL: URL(filePath: "/tmp/chrome")
                ),
                SyncBrowserConfig(
                    browser: .safari,
                    clientID: safariClient,
                    direction: .both,
                    bookmarksFileURL: URL(filePath: "/tmp/safari")
                ),
            ],
            sortAfterImport: false
        )

        let result = try coordinator.runCycle(request: request)

        #expect(result.didWriteStore)
        #expect(result.importedBrowsers == [.chrome, .safari])
        #expect(result.exportedBrowsers == [.chrome, .safari])
        #expect(result.skippedByAntiChurn.isEmpty)

        let safariWritten = try #require(safariAdapter.lastWrittenItems)
        #expect(safariWritten.contains(where: { $0.type == .bookmark && $0.url == "https://example.com" }))
    }

    @Test func deletionInImportBrowserRemovesItemFromCanonicalAndExportTarget() throws {
        let chromeClient = "chrome-client"
        let safariClient = "safari-client"

        let canonical = canonicalItemsWithSharedBookmark(chromeClient: chromeClient, safariClient: safariClient)
        let initial = StoreDocument(
            metadata: StoreMetadata(
                schemaVersion: 1,
                storeRevision: 5,
                writtenByClientID: "seed",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                clients: []
            ),
            items: canonical
        )

        let chromeItems = browserItems(
            clientID: chromeClient,
            barTitle: "Bookmarks Bar",
            bookmarkID: nil,
            bookmarkTitle: nil,
            bookmarkURL: nil
        )
        let safariItems = browserItems(
            clientID: safariClient,
            barTitle: "Favorites Bar",
            bookmarkID: "safari-bookmark-1",
            bookmarkTitle: "Example",
            bookmarkURL: "https://example.com"
        )

        let store = InMemoryStore(document: initial)
        let antiChurn = InMemoryAntiChurnStateStore()
        let chromeAdapter = MockBrowserSyncAdapter(itemsToRead: chromeItems)
        let safariAdapter = MockBrowserSyncAdapter(itemsToRead: safariItems)

        let coordinator = SyncCoordinator(
            store: store,
            adapters: [
                .chrome: chromeAdapter,
                .safari: safariAdapter,
            ],
            antiChurnStateStore: antiChurn
        )

        let request = SyncCycleRequest(
            writerClientID: "sync-mac-1",
            browsers: [
                SyncBrowserConfig(
                    browser: .chrome,
                    clientID: chromeClient,
                    direction: .importOnly,
                    bookmarksFileURL: URL(filePath: "/tmp/chrome")
                ),
                SyncBrowserConfig(
                    browser: .safari,
                    clientID: safariClient,
                    direction: .exportOnly,
                    bookmarksFileURL: URL(filePath: "/tmp/safari")
                ),
            ],
            sortAfterImport: false
        )

        let result = try coordinator.runCycle(request: request)

        #expect(result.didWriteStore)
        let updated = try #require(store.document)
        #expect(updated.items.contains(where: { $0.type == .bookmark }) == false)
        let safariWritten = try #require(safariAdapter.lastWrittenItems)
        #expect(safariWritten.contains(where: { $0.type == .bookmark }) == false)
    }

    @Test func moveInImportBrowserIsExportedToOtherBrowser() throws {
        let chromeClient = "chrome-client"
        let safariClient = "safari-client"

        let chromeItems = browserItems(
            clientID: chromeClient,
            barTitle: "Bookmarks Bar",
            bookmarkID: "chrome-bookmark-1",
            bookmarkTitle: "Moved",
            bookmarkURL: "https://example.com",
            parent: "other"
        )
        let safariItems = browserItems(
            clientID: safariClient,
            barTitle: "Favorites Bar",
            bookmarkID: nil,
            bookmarkTitle: nil,
            bookmarkURL: nil
        )

        let store = InMemoryStore(document: nil)
        let antiChurn = InMemoryAntiChurnStateStore()
        let chromeAdapter = MockBrowserSyncAdapter(itemsToRead: chromeItems)
        let safariAdapter = MockBrowserSyncAdapter(itemsToRead: safariItems)

        let coordinator = SyncCoordinator(
            store: store,
            adapters: [
                .chrome: chromeAdapter,
                .safari: safariAdapter,
            ],
            antiChurnStateStore: antiChurn
        )

        let request = SyncCycleRequest(
            writerClientID: "sync-mac-1",
            browsers: [
                SyncBrowserConfig(
                    browser: .chrome,
                    clientID: chromeClient,
                    direction: .importOnly,
                    bookmarksFileURL: URL(filePath: "/tmp/chrome")
                ),
                SyncBrowserConfig(
                    browser: .safari,
                    clientID: safariClient,
                    direction: .exportOnly,
                    bookmarksFileURL: URL(filePath: "/tmp/safari")
                ),
            ],
            sortAfterImport: false
        )

        _ = try coordinator.runCycle(request: request)
        let safariWritten = try #require(safariAdapter.lastWrittenItems)
        let moved = try #require(safariWritten
            .first(where: { $0.type == .bookmark && $0.url == "https://example.com" }))
        #expect(moved.parentID == "other_bookmarks")
    }

    @Test func secondCycleSkipsImportByAntiChurnAndAvoidsRewrite() throws {
        let chromeClient = "chrome-client"
        let safariClient = "safari-client"

        let chromeItems = browserItems(
            clientID: chromeClient,
            barTitle: "Bookmarks Bar",
            bookmarkID: "chrome-bookmark-1",
            bookmarkTitle: "Example",
            bookmarkURL: "https://example.com"
        )
        let safariItems = browserItems(
            clientID: safariClient,
            barTitle: "Favorites Bar",
            bookmarkID: nil,
            bookmarkTitle: nil,
            bookmarkURL: nil
        )

        let store = InMemoryStore(document: nil)
        let antiChurn = InMemoryAntiChurnStateStore()
        let chromeAdapter = MockBrowserSyncAdapter(itemsToRead: chromeItems)
        let safariAdapter = MockBrowserSyncAdapter(itemsToRead: safariItems)

        let coordinator = SyncCoordinator(
            store: store,
            adapters: [
                .chrome: chromeAdapter,
                .safari: safariAdapter,
            ],
            antiChurnStateStore: antiChurn
        )

        let request = SyncCycleRequest(
            writerClientID: "sync-mac-1",
            browsers: [
                SyncBrowserConfig(
                    browser: .chrome,
                    clientID: chromeClient,
                    direction: .both,
                    bookmarksFileURL: URL(filePath: "/tmp/chrome")
                ),
                SyncBrowserConfig(
                    browser: .safari,
                    clientID: safariClient,
                    direction: .both,
                    bookmarksFileURL: URL(filePath: "/tmp/safari")
                ),
            ],
            sortAfterImport: false
        )

        _ = try coordinator.runCycle(request: request)
        let beforeWrites = store.writeCallCount
        let second = try coordinator.runCycle(request: request)

        #expect(second.didWriteStore == false)
        #expect(Set(second.skippedByAntiChurn) == Set([.chrome, .safari]))
        #expect(store.writeCallCount == beforeWrites)
    }

    @Test func revisionConflictRetriesOnceAndSucceeds() throws {
        let chromeClient = "chrome-client"

        let chromeItems = browserItems(
            clientID: chromeClient,
            barTitle: "Bookmarks Bar",
            bookmarkID: "chrome-bookmark-1",
            bookmarkTitle: "Example",
            bookmarkURL: "https://example.com"
        )

        let initialDocument = StoreDocument(
            metadata: StoreMetadata(
                schemaVersion: 1,
                storeRevision: 1,
                writtenByClientID: "other-client",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                clients: []
            ),
            items: []
        )

        let store = InMemoryStore(document: initialDocument, failFirstWriteWithConflict: true)
        let antiChurn = InMemoryAntiChurnStateStore()
        let chromeAdapter = MockBrowserSyncAdapter(itemsToRead: chromeItems)

        let coordinator = SyncCoordinator(
            store: store,
            adapters: [.chrome: chromeAdapter],
            antiChurnStateStore: antiChurn
        )

        let request = SyncCycleRequest(
            writerClientID: "sync-mac-1",
            browsers: [
                SyncBrowserConfig(
                    browser: .chrome,
                    clientID: chromeClient,
                    direction: .both,
                    bookmarksFileURL: URL(filePath: "/tmp/chrome")
                ),
            ],
            sortAfterImport: false
        )

        let result = try coordinator.runCycle(request: request)

        #expect(result.didWriteStore)
        #expect(store.writeCallCount == 2)
        #expect(result.storeRevision == 3)
    }

    @Test func exportOnlyBrowserStillExportsWhenCanonicalIsUnchanged() throws {
        let safariClient = "safari-client"
        let canonicalItems = browserItems(
            clientID: safariClient,
            barTitle: "Favorites Bar",
            bookmarkID: "safari-bookmark-1",
            bookmarkTitle: "Example",
            bookmarkURL: "https://example.com"
        )

        let initialDocument = StoreDocument(
            metadata: StoreMetadata(
                schemaVersion: 1,
                storeRevision: 7,
                writtenByClientID: "seed",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                clients: []
            ),
            items: canonicalItems
        )

        let store = InMemoryStore(document: initialDocument)
        let antiChurn = InMemoryAntiChurnStateStore()
        let safariAdapter = MockBrowserSyncAdapter(itemsToRead: [])

        let coordinator = SyncCoordinator(
            store: store,
            adapters: [.safari: safariAdapter],
            antiChurnStateStore: antiChurn
        )

        let request = SyncCycleRequest(
            writerClientID: "sync-mac-1",
            browsers: [
                SyncBrowserConfig(
                    browser: .safari,
                    clientID: safariClient,
                    direction: .exportOnly,
                    bookmarksFileURL: URL(filePath: "/tmp/safari")
                ),
            ],
            sortAfterImport: false
        )

        let result = try coordinator.runCycle(request: request)

        #expect(result.didWriteStore == false)
        #expect(result.storeRevision == 7)
        #expect(result.exportedBrowsers == [.safari])
        let written = try #require(safariAdapter.lastWrittenItems)
        #expect(written.contains(where: { $0.type == .bookmark && $0.url == "https://example.com" }))
    }

    @Test func conflictReplayNoOpReportsDidWriteStoreFalse() throws {
        let chromeClient = "chrome-client"
        let chromeItems = browserItems(
            clientID: chromeClient,
            barTitle: "Bookmarks Bar",
            bookmarkID: "chrome-bookmark-1",
            bookmarkTitle: "Example",
            bookmarkURL: "https://example.com"
        )

        let initialDocument = StoreDocument(
            metadata: StoreMetadata(
                schemaVersion: 1,
                storeRevision: 10,
                writtenByClientID: "seed",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                clients: []
            ),
            items: []
        )

        let store = InMemoryStore(
            document: initialDocument,
            failFirstWriteWithConflict: true,
            adoptIncomingItemsOnFirstConflict: true
        )
        let antiChurn = InMemoryAntiChurnStateStore()
        let chromeAdapter = MockBrowserSyncAdapter(itemsToRead: chromeItems)

        let coordinator = SyncCoordinator(
            store: store,
            adapters: [.chrome: chromeAdapter],
            antiChurnStateStore: antiChurn
        )

        let request = SyncCycleRequest(
            writerClientID: "sync-mac-1",
            browsers: [
                SyncBrowserConfig(
                    browser: .chrome,
                    clientID: chromeClient,
                    direction: .both,
                    bookmarksFileURL: URL(filePath: "/tmp/chrome")
                ),
            ],
            sortAfterImport: false
        )

        let result = try coordinator.runCycle(request: request)

        #expect(result.didWriteStore == false)
        #expect(result.storeRevision == 11)
        #expect(store.writeCallCount == 1)
    }

    @Test func safeSyncLimitExceededAbortsBeforeWriteAndExport() throws {
        let chromeClient = "chrome-client"
        let safariClient = "safari-client"

        let chromeItems = browserItems(
            clientID: chromeClient,
            barTitle: "Bookmarks Bar",
            bookmarkID: "chrome-bookmark-1",
            bookmarkTitle: "Example",
            bookmarkURL: "https://example.com"
        )
        let safariItems = browserItems(
            clientID: safariClient,
            barTitle: "Favorites Bar",
            bookmarkID: nil,
            bookmarkTitle: nil,
            bookmarkURL: nil
        )

        let store = InMemoryStore(document: nil)
        let antiChurn = InMemoryAntiChurnStateStore()
        let chromeAdapter = MockBrowserSyncAdapter(itemsToRead: chromeItems)
        let safariAdapter = MockBrowserSyncAdapter(itemsToRead: safariItems)
        let coordinator = SyncCoordinator(
            store: store,
            adapters: [.chrome: chromeAdapter, .safari: safariAdapter],
            antiChurnStateStore: antiChurn
        )

        let request = SyncCycleRequest(
            writerClientID: "sync-mac-1",
            browsers: [
                SyncBrowserConfig(
                    browser: .chrome,
                    clientID: chromeClient,
                    direction: .both,
                    bookmarksFileURL: URL(filePath: "/tmp/chrome")
                ),
                SyncBrowserConfig(
                    browser: .safari,
                    clientID: safariClient,
                    direction: .both,
                    bookmarksFileURL: URL(filePath: "/tmp/safari")
                ),
            ],
            sortAfterImport: false,
            safeSyncLimit: 0
        )

        do {
            _ = try coordinator.runCycle(request: request)
            Issue.record("Expected safe sync limit failure")
        } catch let error as SyncCoordinatorError {
            #expect(error == .safeSyncLimitExceeded(limit: 0, actual: 3))
        }

        #expect(store.writeCallCount == 0)
        #expect(chromeAdapter.lastWrittenItems == nil)
        #expect(safariAdapter.lastWrittenItems == nil)
    }

    @Test func safeSyncLimitAllowsCycleWhenActualEqualsLimit() throws {
        let chromeClient = "chrome-client"

        let chromeItems = browserItems(
            clientID: chromeClient,
            barTitle: "Bookmarks Bar",
            bookmarkID: "chrome-bookmark-1",
            bookmarkTitle: "Example",
            bookmarkURL: "https://example.com"
        )

        let store = InMemoryStore(document: nil)
        let antiChurn = InMemoryAntiChurnStateStore()
        let chromeAdapter = MockBrowserSyncAdapter(itemsToRead: chromeItems)
        let coordinator = SyncCoordinator(
            store: store,
            adapters: [.chrome: chromeAdapter],
            antiChurnStateStore: antiChurn
        )

        let request = SyncCycleRequest(
            writerClientID: "sync-mac-1",
            browsers: [
                SyncBrowserConfig(
                    browser: .chrome,
                    clientID: chromeClient,
                    direction: .both,
                    bookmarksFileURL: URL(filePath: "/tmp/chrome")
                ),
            ],
            sortAfterImport: false,
            safeSyncLimit: 3
        )

        let result = try coordinator.runCycle(request: request)
        #expect(result.didWriteStore)
        #expect(store.writeCallCount == 1)
    }

    @Test func safeSyncLimitAppliesAfterRevisionConflictReplay() throws {
        let chromeClient = "chrome-client"

        let localItems = browserItems(
            clientID: chromeClient,
            barTitle: "Bookmarks Bar",
            bookmarkID: "bookmark-a",
            bookmarkTitle: "A",
            bookmarkURL: "https://a.example.com"
        )
        let baseItems = browserItems(
            clientID: chromeClient,
            barTitle: "Bookmarks Bar",
            bookmarkID: nil,
            bookmarkTitle: nil,
            bookmarkURL: nil
        )
        let conflictItems = conflictCanonicalItems(clientID: chromeClient)

        let initialDocument = StoreDocument(
            metadata: StoreMetadata(
                schemaVersion: 1,
                storeRevision: 1,
                writtenByClientID: "seed",
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                clients: []
            ),
            items: baseItems
        )

        let store = InMemoryStore(
            document: initialDocument,
            failFirstWriteWithConflict: true,
            conflictReplacementItems: conflictItems
        )
        let antiChurn = InMemoryAntiChurnStateStore()
        let chromeAdapter = MockBrowserSyncAdapter(itemsToRead: localItems)
        let coordinator = SyncCoordinator(
            store: store,
            adapters: [.chrome: chromeAdapter],
            antiChurnStateStore: antiChurn
        )

        let request = SyncCycleRequest(
            writerClientID: "sync-mac-1",
            browsers: [
                SyncBrowserConfig(
                    browser: .chrome,
                    clientID: chromeClient,
                    direction: .both,
                    bookmarksFileURL: URL(filePath: "/tmp/chrome")
                ),
            ],
            sortAfterImport: false,
            safeSyncLimit: 1
        )

        do {
            _ = try coordinator.runCycle(request: request)
            Issue.record("Expected safe sync limit failure in replay")
        } catch let error as SyncCoordinatorError {
            #expect(error == .safeSyncLimitExceeded(limit: 1, actual: 2))
        }

        #expect(store.writeCallCount == 1)
        #expect(chromeAdapter.lastWrittenItems == nil)
    }
}

// swiftlint:enable type_body_length function_body_length trailing_comma

private func browserItems(
    clientID: String,
    barTitle: String,
    bookmarkID: String?,
    bookmarkTitle: String?,
    bookmarkURL: String?,
    parent: String = "bar"
) -> [BookmarkItem] {
    let barID = "\(clientID)-bar"
    let otherID = "\(clientID)-other"

    var items: [BookmarkItem] = []
    items.append(
        BookmarkItem(
            id: barID,
            type: .folder,
            parentID: nil,
            position: 0,
            title: barTitle,
            identifierMap: [clientID: barID]
        )
    )
    items.append(
        BookmarkItem(
            id: otherID,
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Other Bookmarks",
            identifierMap: [clientID: otherID]
        )
    )

    if let bookmarkID, let bookmarkTitle, let bookmarkURL {
        let parentID = parent == "other" ? otherID : barID
        items.append(
            BookmarkItem(
                id: bookmarkID,
                type: .bookmark,
                parentID: parentID,
                position: 0,
                title: bookmarkTitle,
                url: bookmarkURL,
                identifierMap: [clientID: bookmarkID]
            )
        )
    }

    return items
}

private func canonicalItemsWithSharedBookmark(chromeClient: String, safariClient: String) -> [BookmarkItem] {
    let chromeBar = "\(chromeClient)-bar"
    let chromeOther = "\(chromeClient)-other"
    let safariBar = "\(safariClient)-bar"
    let safariOther = "\(safariClient)-other"

    var items: [BookmarkItem] = []
    items.append(
        BookmarkItem(
            id: "bookmarks_bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar",
            identifierMap: [chromeClient: chromeBar, safariClient: safariBar]
        )
    )
    items.append(
        BookmarkItem(
            id: "other_bookmarks",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Other Bookmarks",
            identifierMap: [chromeClient: chromeOther, safariClient: safariOther]
        )
    )
    items.append(
        BookmarkItem(
            id: "canonical-bookmark",
            type: .bookmark,
            parentID: "bookmarks_bar",
            position: 0,
            title: "Example",
            url: "https://example.com",
            identifierMap: [chromeClient: "chrome-bookmark-1", safariClient: "safari-bookmark-1"]
        )
    )
    return items
}

// swiftlint:disable:next function_body_length
private func conflictCanonicalItems(clientID: String) -> [BookmarkItem] {
    let barID = "\(clientID)-bar"
    let otherID = "\(clientID)-other"

    var items: [BookmarkItem] = []
    items.append(
        BookmarkItem(
            id: "bookmarks_bar",
            type: .folder,
            parentID: nil,
            position: 0,
            title: "Bookmarks Bar",
            identifierMap: [clientID: barID]
        )
    )
    items.append(
        BookmarkItem(
            id: "other_bookmarks",
            type: .folder,
            parentID: nil,
            position: 1,
            title: "Other Bookmarks",
            identifierMap: [clientID: otherID]
        )
    )
    items.append(
        BookmarkItem(
            id: "canonical-a",
            type: .bookmark,
            parentID: "bookmarks_bar",
            position: 0,
            title: "A",
            url: "https://a.example.com",
            identifierMap: [clientID: "bookmark-a"]
        )
    )
    items.append(
        BookmarkItem(
            id: "canonical-b",
            type: .bookmark,
            parentID: "bookmarks_bar",
            position: 1,
            title: "B",
            url: "https://b.example.com",
            identifierMap: [clientID: "bookmark-b"]
        )
    )
    items.append(
        BookmarkItem(
            id: "canonical-c",
            type: .bookmark,
            parentID: "bookmarks_bar",
            position: 2,
            title: "C",
            url: "https://c.example.com",
            identifierMap: [clientID: "bookmark-c"]
        )
    )
    return items
}

private final class MockBrowserSyncAdapter: BrowserSyncAdapter {
    var itemsToRead: [BookmarkItem]
    var lastWrittenItems: [BookmarkItem]?

    init(itemsToRead: [BookmarkItem]) {
        self.itemsToRead = itemsToRead
    }

    func read(config _: SyncBrowserConfig) throws -> [BookmarkItem] {
        itemsToRead
    }

    func write(items: [BookmarkItem], config _: SyncBrowserConfig) throws {
        lastWrittenItems = items
        itemsToRead = items
    }
}

private final class InMemoryStore: BookmarkStoreClient {
    var document: StoreDocument?
    var writeCallCount = 0
    private var failFirstWriteWithConflict: Bool
    private let adoptIncomingItemsOnFirstConflict: Bool
    private let conflictReplacementItems: [BookmarkItem]?

    init(
        document: StoreDocument?,
        failFirstWriteWithConflict: Bool = false,
        adoptIncomingItemsOnFirstConflict: Bool = false,
        conflictReplacementItems: [BookmarkItem]? = nil
    ) {
        self.document = document
        self.failFirstWriteWithConflict = failFirstWriteWithConflict
        self.adoptIncomingItemsOnFirstConflict = adoptIncomingItemsOnFirstConflict
        self.conflictReplacementItems = conflictReplacementItems
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

        let currentRevision = document?.metadata.storeRevision ?? 0
        if let expectedStoreRevision, expectedStoreRevision != currentRevision {
            throw BookmarkStoreError.revisionConflict(expected: expectedStoreRevision, actual: currentRevision)
        }

        if failFirstWriteWithConflict {
            failFirstWriteWithConflict = false
            document = StoreDocument(
                metadata: StoreMetadata(
                    schemaVersion: BookmarkStore.schemaVersion,
                    storeRevision: currentRevision + 1,
                    writtenByClientID: "external",
                    updatedAt: now,
                    clients: clients
                ),
                items: conflictReplacementItems
                    ?? (adoptIncomingItemsOnFirstConflict ? items : (document?.items ?? []))
            )
            throw BookmarkStoreError.revisionConflict(expected: currentRevision, actual: currentRevision + 1)
        }

        let updated = StoreDocument(
            metadata: StoreMetadata(
                schemaVersion: BookmarkStore.schemaVersion,
                storeRevision: currentRevision + 1,
                writtenByClientID: writerClientID,
                updatedAt: now,
                clients: clients
            ),
            items: items
        )
        document = updated
        return updated
    }
}
