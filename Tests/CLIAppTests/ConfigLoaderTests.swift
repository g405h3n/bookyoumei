@testable import CLIApp
import Foundation
import Testing

@Suite("ConfigLoader")
struct ConfigLoaderTests {
    @Test func configDefaultsSafeSyncLimitTo100() throws {
        try withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("config.yaml")
            try Data(
                """
                writer_client_id: writer-client
                chrome_client_id: chrome-client
                safari_client_id: safari-client
                """.utf8
            ).write(to: configURL)

            let loader = ConfigLoader(fileManager: .default)
            let config = try loader.load(configPathOverride: configURL.path)

            #expect(config.safeSyncLimit == 100)
        }
    }

    @Test func configLoadFailsWhenSafeSyncLimitIsNonInteger() throws {
        try withTemporaryDirectory { directory in
            let configURL = directory.appendingPathComponent("config.yaml")
            try Data(
                """
                writer_client_id: writer-client
                chrome_client_id: chrome-client
                safe_sync_limit: abc
                """.utf8
            ).write(to: configURL)

            let loader = ConfigLoader(fileManager: .default)

            do {
                _ = try loader.load(configPathOverride: configURL.path)
                Issue.record("Expected ConfigLoader.load to fail for non-integer safe_sync_limit")
            } catch let error as CLIError {
                guard case let .invalidArguments(message) = error else {
                    Issue.record("Unexpected CLIError case: \(error)")
                    return
                }
                #expect(message.contains("invalid safe_sync_limit"))
            }
        }
    }
}
