import Foundation

public struct LogEntry: Equatable {
    public let timestamp: Date
    public let level: String
    public let message: String

    public init(timestamp: Date, level: String, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

public protocol LogStoring {
    func append(level: String, message: String, now: Date) throws
    func readEntries() throws -> [LogEntry]
}

public final class LogStore: LogStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private let formatter: ISO8601DateFormatter

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
    }

    public func append(level: String, message: String, now: Date) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let timestamp = formatter.string(from: now)
        let line = "\(timestamp) \(level) \(message)\n"
        let data = Data(line.utf8)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: .atomic)
        }
    }

    public func readEntries() throws -> [LogEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return text
            .split(separator: "\n")
            .compactMap(parseLine)
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func parseLine(_ line: Substring) -> LogEntry? {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3 else { return nil }
        guard let timestamp = formatter.date(from: String(parts[0])) else { return nil }

        return LogEntry(
            timestamp: timestamp,
            level: String(parts[1]),
            message: String(parts[2])
        )
    }
}
