import Foundation

public enum WatchSource: String, CaseIterable, Sendable {
    case chromeBookmarks
    case safariBookmarks
    case storeJSON
}

public struct WatcherConfig: Sendable {
    public let coalesceDelaySeconds: TimeInterval
    public let watchedPaths: [WatchSource: URL]

    public init(coalesceDelaySeconds: TimeInterval, watchedPaths: [WatchSource: URL]) {
        self.coalesceDelaySeconds = coalesceDelaySeconds
        self.watchedPaths = watchedPaths
    }
}
