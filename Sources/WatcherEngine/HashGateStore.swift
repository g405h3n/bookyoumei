import Foundation

public protocol HashGateStore {
    func loadLastHash(for source: WatchSource) -> String?
    func saveLastHash(_ hash: String, for source: WatchSource)
}

public final class InMemoryHashGateStore: HashGateStore {
    private var storage: [WatchSource: String] = [:]

    public init() {}

    public func loadLastHash(for source: WatchSource) -> String? {
        storage[source]
    }

    public func saveLastHash(_ hash: String, for source: WatchSource) {
        storage[source] = hash
    }
}
