@testable import CLIApp
import Foundation
import Testing

@Suite("DaemonControl")
struct DaemonControlTests {
    @Test func pausePersistsFlagAndStopsRuntime() throws {
        try withTemporaryDirectory { directory in
            let runtime = StubRuntimeController()
            let control = DaemonControl(
                stateDirectoryURL: directory,
                runtimeController: runtime,
                fileManager: .default
            )

            try control.pause()

            #expect(runtime.stopCallCount == 1)
            #expect(FileManager.default.fileExists(atPath: control.pauseFlagURL.path))
        }
    }

    @Test func pauseIsIdempotentWhenAlreadyPaused() throws {
        try withTemporaryDirectory { directory in
            let runtime = StubRuntimeController()
            let control = DaemonControl(
                stateDirectoryURL: directory,
                runtimeController: runtime,
                fileManager: .default
            )

            try control.pause()
            try control.pause()

            #expect(runtime.stopCallCount == 1)
        }
    }

    @Test func resumeClearsFlagAndStartsRuntime() throws {
        try withTemporaryDirectory { directory in
            let runtime = StubRuntimeController()
            let control = DaemonControl(
                stateDirectoryURL: directory,
                runtimeController: runtime,
                fileManager: .default
            )

            try control.pause()
            try control.resume()

            #expect(runtime.startCallCount == 1)
            #expect(!FileManager.default.fileExists(atPath: control.pauseFlagURL.path))
        }
    }

    @Test func resumeIsIdempotentWhenAlreadyActive() throws {
        try withTemporaryDirectory { directory in
            let runtime = StubRuntimeController()
            let control = DaemonControl(
                stateDirectoryURL: directory,
                runtimeController: runtime,
                fileManager: .default
            )

            try control.resume()
            try control.resume()

            #expect(runtime.startCallCount == 0)
        }
    }
}
