import Foundation
import SyncEngine

public protocol SyncCycleRunning {
    func runCycle(request: SyncCycleRequest) throws -> SyncCycleResult
}

extension SyncCoordinator: SyncCycleRunning {}

public final class SyncCoordinatorDispatcher: SyncCycleDispatcher {
    private let runner: SyncCycleRunning
    private let requestProvider: @Sendable () -> SyncCycleRequest
    private let onError: @Sendable (Error) -> Void

    public init(
        runner: SyncCycleRunning,
        requestProvider: @escaping @Sendable () -> SyncCycleRequest,
        onError: @escaping @Sendable (Error) -> Void = { _ in }
    ) {
        self.runner = runner
        self.requestProvider = requestProvider
        self.onError = onError
    }

    public func dispatch(completion: @escaping () -> Void) {
        defer { completion() }
        do {
            _ = try runner.runCycle(request: requestProvider())
        } catch {
            onError(error)
        }
    }
}

public struct WatcherRuntimeBootstrap {
    public let coordinator: FilesystemWatcherCoordinator
    public let dispatcher: SyncCoordinatorDispatcher

    public init(
        config: WatcherConfig,
        eventSource: WatchEventSource,
        scheduler: WatcherScheduler,
        hasher: FileContentHasher,
        hashStore: HashGateStore,
        syncRunner: SyncCycleRunning,
        requestProvider: @escaping @Sendable () -> SyncCycleRequest,
        onSyncError: @escaping @Sendable (Error) -> Void = { _ in }
    ) {
        let dispatcher = SyncCoordinatorDispatcher(
            runner: syncRunner,
            requestProvider: requestProvider,
            onError: onSyncError
        )

        self.dispatcher = dispatcher
        coordinator = FilesystemWatcherCoordinator(
            config: config,
            eventSource: eventSource,
            scheduler: scheduler,
            hasher: hasher,
            hashStore: hashStore,
            dispatcher: dispatcher
        )
    }
}
