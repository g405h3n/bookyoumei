import Foundation
@testable import SyncEngine
import Testing
@testable import WatcherEngine

// swiftlint:disable file_length
// swiftlint:disable trailing_comma
@Suite("FilesystemWatcherCoordinator")
struct FilesystemWatcherCoordinatorTests {
    @Test func startupSeedsBaselineHashesWithoutInitialDispatch() throws {
        let scheduler = TestWatcherScheduler()
        let eventSource = TestWatchEventSource()
        let hasher = TestFileContentHasher()
        let hashStore = InMemoryHashGateStore()
        let dispatcher = TestSyncCycleDispatcher()
        let urls = testURLs()

        try hasher.setHash("chrome-v1", for: #require(urls[.chromeBookmarks]))
        try hasher.setHash("safari-v1", for: #require(urls[.safariBookmarks]))
        try hasher.setHash("store-v1", for: #require(urls[.storeJSON]))

        let coordinator = FilesystemWatcherCoordinator(
            config: WatcherConfig(coalesceDelaySeconds: 60, watchedPaths: urls),
            eventSource: eventSource,
            scheduler: scheduler,
            hasher: hasher,
            hashStore: hashStore,
            dispatcher: dispatcher
        )

        coordinator.start()

        #expect(dispatcher.dispatchCallCount == 0)
        #expect(hashStore.loadLastHash(for: .chromeBookmarks) == "chrome-v1")
        #expect(hashStore.loadLastHash(for: .safariBookmarks) == "safari-v1")
        #expect(hashStore.loadLastHash(for: .storeJSON) == "store-v1")
    }

    @Test func coalescesBurstEventsIntoSingleDispatch() throws {
        let harness = makeHarness()
        let coordinator = harness.coordinator
        let eventSource = harness.eventSource
        let scheduler = harness.scheduler
        let hasher = harness.hasher
        let dispatcher = harness.dispatcher
        let urls = harness.urls
        try hasher.setHash("chrome-v1", for: #require(urls[.chromeBookmarks]))
        coordinator.start()

        try hasher.setHash("chrome-v2", for: #require(urls[.chromeBookmarks]))
        eventSource.emit(.chromeBookmarks)
        eventSource.emit(.chromeBookmarks)
        eventSource.emit(.chromeBookmarks)

        #expect(dispatcher.dispatchCallCount == 0)
        scheduler.fire(for: .chromeBookmarks)
        #expect(dispatcher.dispatchCallCount == 1)
    }

    @Test func noOpRewriteWithSameHashSkipsDispatch() throws {
        let harness = makeHarness()
        let coordinator = harness.coordinator
        let eventSource = harness.eventSource
        let scheduler = harness.scheduler
        let hasher = harness.hasher
        let dispatcher = harness.dispatcher
        let urls = harness.urls
        try hasher.setHash("chrome-v1", for: #require(urls[.chromeBookmarks]))
        coordinator.start()

        try hasher.setHash("chrome-v1", for: #require(urls[.chromeBookmarks]))
        eventSource.emit(.chromeBookmarks)
        scheduler.fire(for: .chromeBookmarks)

        #expect(dispatcher.dispatchCallCount == 0)
    }

    @Test func changedHashAfterDelayDispatches() throws {
        let harness = makeHarness()
        let coordinator = harness.coordinator
        let eventSource = harness.eventSource
        let scheduler = harness.scheduler
        let hasher = harness.hasher
        let dispatcher = harness.dispatcher
        let urls = harness.urls
        try hasher.setHash("chrome-v1", for: #require(urls[.chromeBookmarks]))
        coordinator.start()

        try hasher.setHash("chrome-v2", for: #require(urls[.chromeBookmarks]))
        eventSource.emit(.chromeBookmarks)
        scheduler.fire(for: .chromeBookmarks)

        #expect(dispatcher.dispatchCallCount == 1)
    }

    @Test func distinctSourcesMaintainSeparateCoalesceWindows() throws {
        let harness = makeHarness()
        let coordinator = harness.coordinator
        let eventSource = harness.eventSource
        let scheduler = harness.scheduler
        let hasher = harness.hasher
        let dispatcher = harness.dispatcher
        let urls = harness.urls
        try hasher.setHash("chrome-v1", for: #require(urls[.chromeBookmarks]))
        try hasher.setHash("safari-v1", for: #require(urls[.safariBookmarks]))
        coordinator.start()

        try hasher.setHash("chrome-v2", for: #require(urls[.chromeBookmarks]))
        try hasher.setHash("safari-v2", for: #require(urls[.safariBookmarks]))
        eventSource.emit(.chromeBookmarks)
        eventSource.emit(.safariBookmarks)

        scheduler.fire(for: .chromeBookmarks)
        #expect(dispatcher.dispatchCallCount == 1)

        scheduler.fire(for: .safariBookmarks)
        #expect(dispatcher.dispatchCallCount == 1)

        dispatcher.completeNextDispatch()
        #expect(dispatcher.dispatchCallCount == 2)
    }

    @Test func eventsDuringInFlightCycleQueueSingleFollowUpDispatch() throws {
        let harness = makeHarness()
        let coordinator = harness.coordinator
        let eventSource = harness.eventSource
        let scheduler = harness.scheduler
        let hasher = harness.hasher
        let dispatcher = harness.dispatcher
        let urls = harness.urls
        try hasher.setHash("chrome-v1", for: #require(urls[.chromeBookmarks]))
        coordinator.start()

        try hasher.setHash("chrome-v2", for: #require(urls[.chromeBookmarks]))
        eventSource.emit(.chromeBookmarks)
        scheduler.fire(for: .chromeBookmarks)
        #expect(dispatcher.dispatchCallCount == 1)

        try hasher.setHash("chrome-v3", for: #require(urls[.chromeBookmarks]))
        eventSource.emit(.chromeBookmarks)
        eventSource.emit(.chromeBookmarks)
        scheduler.fire(for: .chromeBookmarks)
        #expect(dispatcher.dispatchCallCount == 1)

        dispatcher.completeNextDispatch()
        #expect(dispatcher.dispatchCallCount == 2)
    }

    @Test func hashReadFailureSkipsDispatchAndRetainsWatcherLiveness() throws {
        let harness = makeHarness()
        let coordinator = harness.coordinator
        let eventSource = harness.eventSource
        let scheduler = harness.scheduler
        let hasher = harness.hasher
        let dispatcher = harness.dispatcher
        let urls = harness.urls
        try hasher.setHash("chrome-v1", for: #require(urls[.chromeBookmarks]))
        coordinator.start()

        try hasher.setError(for: #require(urls[.chromeBookmarks]))
        eventSource.emit(.chromeBookmarks)
        scheduler.fire(for: .chromeBookmarks)
        #expect(dispatcher.dispatchCallCount == 0)

        try hasher.clearError(for: #require(urls[.chromeBookmarks]))
        try hasher.setHash("chrome-v2", for: #require(urls[.chromeBookmarks]))
        eventSource.emit(.chromeBookmarks)
        scheduler.fire(for: .chromeBookmarks)
        #expect(dispatcher.dispatchCallCount == 1)
    }

    @Test func startupSeedFailureDispatchesOnFirstSuccessfulGate() throws {
        let harness = makeHarness()
        let coordinator = harness.coordinator
        let eventSource = harness.eventSource
        let scheduler = harness.scheduler
        let hasher = harness.hasher
        let dispatcher = harness.dispatcher
        let urls = harness.urls
        let chromeURL = try #require(urls[.chromeBookmarks])

        hasher.setError(for: chromeURL)
        coordinator.start()

        hasher.clearError(for: chromeURL)
        hasher.setHash("chrome-v2", for: chromeURL)
        eventSource.emit(.chromeBookmarks)
        scheduler.fire(for: .chromeBookmarks)

        #expect(dispatcher.dispatchCallCount == 1)
    }

    @Test func syncCoordinatorDispatcherInvokesRunnerAndCompletes() {
        let request = SyncCycleRequest(writerClientID: "sync-mac-1", browsers: [], sortAfterImport: false)
        let runner = MockSyncCycleRunner()
        var completionCount = 0

        let dispatcher = SyncCoordinatorDispatcher(
            runner: runner,
            requestProvider: { request }
        )

        dispatcher.dispatch {
            completionCount += 1
        }

        #expect(runner.runCallCount == 1)
        #expect(runner.lastRequest?.writerClientID == "sync-mac-1")
        #expect(completionCount == 1)
    }

    @Test func watcherRuntimeBootstrapWiresConcreteDispatcher() throws {
        let eventSource = TestWatchEventSource()
        let scheduler = TestWatcherScheduler()
        let hasher = TestFileContentHasher()
        let hashStore = InMemoryHashGateStore()
        let runner = MockSyncCycleRunner()
        let urls = testURLs()
        try hasher.setHash("chrome-v1", for: #require(urls[.chromeBookmarks]))

        let request = SyncCycleRequest(writerClientID: "sync-mac-1", browsers: [], sortAfterImport: false)
        let runtime = WatcherRuntimeBootstrap(
            config: WatcherConfig(coalesceDelaySeconds: 60, watchedPaths: urls),
            eventSource: eventSource,
            scheduler: scheduler,
            hasher: hasher,
            hashStore: hashStore,
            syncRunner: runner,
            requestProvider: { request }
        )

        runtime.coordinator.start()
        try hasher.setHash("chrome-v2", for: #require(urls[.chromeBookmarks]))
        eventSource.emit(.chromeBookmarks)
        scheduler.fire(for: .chromeBookmarks)

        #expect(runner.runCallCount == 1)
    }

    @Test func concurrentEmitAndCompletionStressMaintainsSingleFlight() throws {
        let scheduler = ConcurrentTestWatcherScheduler()
        let eventSource = ConcurrentTestWatchEventSource()
        let hasher = TestFileContentHasher()
        let hashStore = InMemoryHashGateStore()
        let dispatcher = StressSyncCycleDispatcher()
        let urls = testURLs()

        try hasher.setHash("chrome-v1", for: #require(urls[.chromeBookmarks]))
        let coordinator = FilesystemWatcherCoordinator(
            config: WatcherConfig(coalesceDelaySeconds: 0.01, watchedPaths: urls),
            eventSource: eventSource,
            scheduler: scheduler,
            hasher: hasher,
            hashStore: hashStore,
            dispatcher: dispatcher
        )
        coordinator.start()

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            hasher.setHash("chrome-\(index + 2)", for: urls[.chromeBookmarks]!)
            eventSource.emit(.chromeBookmarks)
            scheduler.fire(for: .chromeBookmarks)
        }

        waitUntil(timeoutSeconds: 2.0) {
            dispatcher.dispatchCallCount > 0 && dispatcher.inFlightCount == 0
        }

        #expect(dispatcher.maxInFlightCount == 1)
        #expect(dispatcher.dispatchCallCount > 0)
    }
}

private struct WatcherTestHarness {
    let coordinator: FilesystemWatcherCoordinator
    let eventSource: TestWatchEventSource
    let scheduler: TestWatcherScheduler
    let hasher: TestFileContentHasher
    let hashStore: InMemoryHashGateStore
    let dispatcher: TestSyncCycleDispatcher
    let urls: [WatchSource: URL]
}

private func makeHarness() -> WatcherTestHarness {
    let scheduler = TestWatcherScheduler()
    let eventSource = TestWatchEventSource()
    let hasher = TestFileContentHasher()
    let hashStore = InMemoryHashGateStore()
    let dispatcher = TestSyncCycleDispatcher()
    let urls = testURLs()

    let coordinator = FilesystemWatcherCoordinator(
        config: WatcherConfig(coalesceDelaySeconds: 60, watchedPaths: urls),
        eventSource: eventSource,
        scheduler: scheduler,
        hasher: hasher,
        hashStore: hashStore,
        dispatcher: dispatcher
    )

    return WatcherTestHarness(
        coordinator: coordinator,
        eventSource: eventSource,
        scheduler: scheduler,
        hasher: hasher,
        hashStore: hashStore,
        dispatcher: dispatcher,
        urls: urls
    )
}

private func testURLs() -> [WatchSource: URL] {
    [
        .chromeBookmarks: URL(filePath: "/tmp/chrome-bookmarks"),
        .safariBookmarks: URL(filePath: "/tmp/safari-bookmarks"),
        .storeJSON: URL(filePath: "/tmp/store-json"),
    ]
}

private final class TestWatchEventSource: WatchEventSource {
    private var onEvent: ((WatchSource) -> Void)?

    func start(onEvent: @escaping (WatchSource) -> Void) {
        self.onEvent = onEvent
    }

    func stop() {
        onEvent = nil
    }

    func emit(_ source: WatchSource) {
        onEvent?(source)
    }
}

private final class ConcurrentTestWatchEventSource: WatchEventSource {
    private let lock = NSLock()
    private var onEvent: ((WatchSource) -> Void)?

    func start(onEvent: @escaping (WatchSource) -> Void) {
        lock.lock()
        self.onEvent = onEvent
        lock.unlock()
    }

    func stop() {
        lock.lock()
        onEvent = nil
        lock.unlock()
    }

    func emit(_ source: WatchSource) {
        lock.lock()
        let callback = onEvent
        lock.unlock()
        callback?(source)
    }
}

private final class TestWatcherScheduler: WatcherScheduler {
    private var tasks: [WatchSource: () -> Void] = [:]

    func schedule(source: WatchSource, after _: TimeInterval, action: @escaping () -> Void) {
        tasks[source] = action
    }

    func cancel(source: WatchSource) {
        tasks[source] = nil
    }

    func fire(for source: WatchSource) {
        let task = tasks[source]
        tasks[source] = nil
        task?()
    }
}

private final class ConcurrentTestWatcherScheduler: WatcherScheduler {
    private let lock = NSLock()
    private var tasks: [WatchSource: () -> Void] = [:]

    func schedule(source: WatchSource, after _: TimeInterval, action: @escaping () -> Void) {
        lock.lock()
        tasks[source] = action
        lock.unlock()
    }

    func cancel(source: WatchSource) {
        lock.lock()
        tasks[source] = nil
        lock.unlock()
    }

    func fire(for source: WatchSource) {
        lock.lock()
        let task = tasks[source]
        tasks[source] = nil
        lock.unlock()
        task?()
    }
}

private enum TestHashError: Error {
    case unreadable
}

private final class TestFileContentHasher: FileContentHasher {
    private let lock = NSLock()
    private var hashes: [URL: String] = [:]
    private var erroredURLs: Set<URL> = []

    func hash(of fileURL: URL) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        if erroredURLs.contains(fileURL) {
            throw TestHashError.unreadable
        }
        return hashes[fileURL] ?? ""
    }

    func setHash(_ hash: String, for fileURL: URL) {
        lock.lock()
        hashes[fileURL] = hash
        lock.unlock()
    }

    func setError(for fileURL: URL) {
        lock.lock()
        erroredURLs.insert(fileURL)
        lock.unlock()
    }

    func clearError(for fileURL: URL) {
        lock.lock()
        erroredURLs.remove(fileURL)
        lock.unlock()
    }
}

private final class TestSyncCycleDispatcher: SyncCycleDispatcher {
    private var completions: [() -> Void] = []
    private(set) var dispatchCallCount = 0

    func dispatch(completion: @escaping () -> Void) {
        dispatchCallCount += 1
        completions.append(completion)
    }

    func completeNextDispatch() {
        guard !completions.isEmpty else { return }
        let completion = completions.removeFirst()
        completion()
    }
}

private final class StressSyncCycleDispatcher: SyncCycleDispatcher {
    private let lock = NSLock()
    private(set) var dispatchCallCount = 0
    private(set) var inFlightCount = 0
    private(set) var maxInFlightCount = 0

    func dispatch(completion: @escaping () -> Void) {
        lock.lock()
        dispatchCallCount += 1
        inFlightCount += 1
        maxInFlightCount = max(maxInFlightCount, inFlightCount)
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.001) { [weak self] in
            self?.lock.lock()
            if let self {
                inFlightCount -= 1
            }
            self?.lock.unlock()
            completion()
        }
    }
}

private final class MockSyncCycleRunner: SyncCycleRunning {
    private(set) var runCallCount = 0
    private(set) var lastRequest: SyncCycleRequest?

    func runCycle(request: SyncCycleRequest) throws -> SyncCycleResult {
        runCallCount += 1
        lastRequest = request
        return SyncCycleResult(
            didWriteStore: true,
            storeRevision: 1,
            importedBrowsers: [],
            exportedBrowsers: [],
            skippedByAntiChurn: []
        )
    }
}

private func waitUntil(timeoutSeconds: TimeInterval, condition: () -> Bool) {
    let end = Date().addingTimeInterval(timeoutSeconds)
    while Date() < end {
        if condition() {
            return
        }
        Thread.sleep(forTimeInterval: 0.005)
    }
}

// swiftlint:enable trailing_comma
// swiftlint:enable file_length
