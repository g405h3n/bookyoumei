@testable import CLIApp
import Foundation
import Testing

@Suite("LogStore")
struct LogStoreTests {
    @Test func logsPrintsEntriesInOrder() throws {
        try withTemporaryDirectory { directory in
            let logFileURL = directory.appendingPathComponent("events.log")
            let store = LogStore(fileURL: logFileURL, fileManager: .default)

            try store.append(level: "INFO", message: "sync done", now: Date(timeIntervalSince1970: 10))
            try store.append(level: "ERROR", message: "sync failed", now: Date(timeIntervalSince1970: 20))

            let entries = try store.readEntries()

            #expect(entries.count == 2)
            #expect(entries[0].message == "sync done")
            #expect(entries[1].message == "sync failed")
        }
    }

    @Test func logsEmptyStateMessage() throws {
        try withTemporaryDirectory { directory in
            let logFileURL = directory.appendingPathComponent("events.log")
            let store = LogStore(fileURL: logFileURL, fileManager: .default)
            let entries = try store.readEntries()

            #expect(entries.isEmpty)
        }
    }
}
