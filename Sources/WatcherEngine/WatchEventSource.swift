import Foundation

public protocol WatchEventSource {
    func start(onEvent: @escaping (WatchSource) -> Void)
    func stop()
}
