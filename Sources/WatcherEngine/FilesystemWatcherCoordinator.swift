import Foundation

public final class FilesystemWatcherCoordinator {
    private let config: WatcherConfig
    private let eventSource: WatchEventSource
    private let scheduler: WatcherScheduler
    private let hasher: FileContentHasher
    private let hashStore: HashGateStore
    private let dispatcher: SyncCycleDispatcher
    private let executorQueue = DispatchQueue(label: "bookmarknot.watcher.coordinator")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var isDispatchInFlight = false
    private var hasQueuedRerun = false
    private var requiresFirstDispatchAfterSeedFailure: Set<WatchSource> = []

    public init(
        config: WatcherConfig,
        eventSource: WatchEventSource,
        scheduler: WatcherScheduler,
        hasher: FileContentHasher,
        hashStore: HashGateStore,
        dispatcher: SyncCycleDispatcher
    ) {
        self.config = config
        self.eventSource = eventSource
        self.scheduler = scheduler
        self.hasher = hasher
        self.hashStore = hashStore
        self.dispatcher = dispatcher
        executorQueue.setSpecific(key: queueKey, value: 1)
    }

    public func start() {
        executeOnQueue {
            seedInitialHashes()
        }
        eventSource.start { [weak self] source in
            self?.executeOnQueue {
                self?.scheduleGate(for: source)
            }
        }
    }

    public func stop() {
        executeOnQueue {
            for source in WatchSource.allCases {
                scheduler.cancel(source: source)
            }
            eventSource.stop()
            isDispatchInFlight = false
            hasQueuedRerun = false
            requiresFirstDispatchAfterSeedFailure = []
        }
    }

    private func scheduleGate(for source: WatchSource) {
        scheduler.schedule(source: source, after: config.coalesceDelaySeconds) { [weak self] in
            self?.executeOnQueue {
                self?.evaluate(source: source)
            }
        }
    }

    private func evaluate(source: WatchSource) {
        guard let url = config.watchedPaths[source] else {
            return
        }

        guard let hash = try? hasher.hash(of: url) else {
            return
        }

        guard let baseline = hashStore.loadLastHash(for: source) else {
            hashStore.saveLastHash(hash, for: source)
            if requiresFirstDispatchAfterSeedFailure.contains(source) {
                requiresFirstDispatchAfterSeedFailure.remove(source)
                requestDispatch()
            }
            return
        }

        guard hash != baseline else {
            return
        }

        hashStore.saveLastHash(hash, for: source)
        requestDispatch()
    }

    private func requestDispatch() {
        if isDispatchInFlight {
            hasQueuedRerun = true
            return
        }

        startDispatch()
    }

    private func startDispatch() {
        isDispatchInFlight = true
        dispatcher.dispatch { [weak self] in
            self?.executeOnQueue {
                self?.handleDispatchCompletion()
            }
        }
    }

    private func handleDispatchCompletion() {
        if hasQueuedRerun {
            hasQueuedRerun = false
            startDispatch()
            return
        }

        isDispatchInFlight = false
    }

    private func seedInitialHashes() {
        for (source, url) in config.watchedPaths {
            guard let hash = try? hasher.hash(of: url) else {
                requiresFirstDispatchAfterSeedFailure.insert(source)
                continue
            }
            hashStore.saveLastHash(hash, for: source)
            requiresFirstDispatchAfterSeedFailure.remove(source)
        }
    }

    private func executeOnQueue(_ operation: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) == 1 {
            operation()
            return
        }
        executorQueue.sync(execute: operation)
    }
}
