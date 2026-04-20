import Foundation

public protocol AntiChurnStateStore {
    func lastExportSignature(for clientID: String) -> String?
    func setLastExportSignature(_ signature: String, for clientID: String)
}

public final class InMemoryAntiChurnStateStore: AntiChurnStateStore {
    private var signatures: [String: String] = [:]

    public init() {}

    public func lastExportSignature(for clientID: String) -> String? {
        signatures[clientID]
    }

    public func setLastExportSignature(_ signature: String, for clientID: String) {
        signatures[clientID] = signature
    }
}
