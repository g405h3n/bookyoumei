import Foundation

public protocol WatcherScheduler {
    func schedule(source: WatchSource, after: TimeInterval, action: @escaping () -> Void)
    func cancel(source: WatchSource)
}
