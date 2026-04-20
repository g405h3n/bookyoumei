import Foundation

public protocol FileContentHasher {
    func hash(of fileURL: URL) throws -> String
}
