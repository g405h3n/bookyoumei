import Foundation

public protocol SyncCycleDispatcher {
    func dispatch(completion: @escaping () -> Void)
}
