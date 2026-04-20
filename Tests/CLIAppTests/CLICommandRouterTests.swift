@testable import CLIApp
import Foundation
import SyncEngine
import Testing

@Suite("CLICommandRouter")
struct CLICommandRouterTests {
    @Test func routesSyncCommand() {
        let harness = RouterHarness()
        let exitCode = harness.router.execute(arguments: ["sync"], io: harness.testIO)

        #expect(exitCode == 0)
        #expect(harness.syncService.runSyncCallCount == 1)
    }

    @Test func routesPauseResumeResetLogsCommands() {
        let harness = RouterHarness()
        let statePath = harness.configLoader.config.stateDirectoryURL.path
        let logPath = harness.configLoader.config.logFileURL.path

        #expect(harness.router.execute(arguments: ["pause"], io: harness.testIO) == 0)
        #expect(harness.daemonControlBuilder.daemonControl(forStatePath: statePath)?.pauseCallCount == 1)

        #expect(harness.router.execute(arguments: ["resume"], io: harness.testIO) == 0)
        #expect(harness.daemonControlBuilder.daemonControl(forStatePath: statePath)?.resumeCallCount == 1)

        #expect(harness.router.execute(arguments: ["logs"], io: harness.testIO) == 0)
        #expect(harness.logStoreBuilder.logStore(forLogPath: logPath)?.readEntriesCallCount == 1)

        #expect(harness.router.execute(arguments: ["reset"], io: harness.testIO) == 0)
        #expect(harness.resetServiceBuilder.builtService.resetCallCount == 1)
    }

    @Test func unknownCommandReturnsUsageError() {
        let harness = RouterHarness()
        let exitCode = harness.router.execute(arguments: ["unknown"], io: harness.testIO)

        #expect(exitCode == 2)
        #expect(harness.testIO.stderr.contains { $0.contains("usage") })
    }

    @Test func syncFailureReturnsNonZeroExitCode() {
        let harness = RouterHarness()
        // swiftlint:disable trailing_comma
        harness.syncService.runSyncError = NSError(domain: "CLIAppTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "sync failed",
        ])
        // swiftlint:enable trailing_comma

        let exitCode = harness.router.execute(arguments: ["sync"], io: harness.testIO)

        #expect(exitCode == 1)
        #expect(harness.testIO.stderr.contains { $0.contains("sync failed") })
    }

    @Test func syncFailsFastWhenConfigIsMissingRequiredPaths() {
        let harness = RouterHarness()
        harness.configLoader.config = RuntimeConfig.missingForSync()

        let exitCode = harness.router.execute(arguments: ["sync"], io: harness.testIO)

        #expect(exitCode == 1)
        #expect(harness.syncService.runSyncCallCount == 0)
        #expect(harness.testIO.stderr.contains { $0.contains("missing required path") })
    }

    @Test func configOverrideAffectsPauseResumeAndLogsPaths() {
        let harness = RouterHarness()
        let overrideConfig = RuntimeConfig.fixture(
            stateDirectoryURL: URL(fileURLWithPath: "/tmp/state-override"),
            logFileURL: URL(fileURLWithPath: "/tmp/logs-override/events.log")
        )
        harness.configLoader.config = overrideConfig

        #expect(harness.router.execute(arguments: ["--config", "/tmp/custom.yaml", "pause"], io: harness.testIO) == 0)
        #expect(harness.router.execute(arguments: ["--config", "/tmp/custom.yaml", "resume"], io: harness.testIO) == 0)
        #expect(harness.router.execute(arguments: ["--config", "/tmp/custom.yaml", "logs"], io: harness.testIO) == 0)

        #expect(harness.configLoader.lastConfigPathOverride == "/tmp/custom.yaml")
        #expect(harness.daemonControlBuilder.daemonControl(forStatePath: "/tmp/state-override")?.pauseCallCount == 1)
        #expect(harness.daemonControlBuilder.daemonControl(forStatePath: "/tmp/state-override")?.resumeCallCount == 1)
        #expect(harness.logStoreBuilder.logStore(forLogPath: "/tmp/logs-override/events.log")?
            .readEntriesCallCount == 1)
    }

    @Test func configLoadFailureExitsNonZeroWithoutFallback() {
        let harness = RouterHarness()
        harness.configLoader.loadError = CLIError.configNotFound("/tmp/missing-config.yaml")

        let exitCode = harness.router.execute(arguments: ["sync"], io: harness.testIO)

        #expect(exitCode == 1)
        #expect(harness.syncService.runSyncCallCount == 0)
        #expect(harness.testIO.stderr.contains { $0.contains("config file not found") })
    }

    @Test func resetFailsWhenClientIdentityIsMissing() {
        let harness = RouterHarness()
        harness.configLoader.config = RuntimeConfig.fixture(
            chromeClientID: nil,
            safariClientID: nil
        )

        let exitCode = harness.router.execute(arguments: ["reset"], io: harness.testIO)

        #expect(exitCode == 1)
        #expect(harness.resetServiceBuilder.builtService.resetCallCount == 0)
        #expect(harness.testIO.stderr.contains { $0.contains("missing required path: client_id") })
    }

    @Test func syncFailsWhenSafeSyncLimitIsNegative() {
        let harness = RouterHarness()
        harness.configLoader.config = RuntimeConfig.fixture(safeSyncLimit: -1)

        let exitCode = harness.router.execute(arguments: ["sync"], io: harness.testIO)

        #expect(exitCode == 2)
        #expect(harness.syncService.runSyncCallCount == 0)
        #expect(harness.testIO.stderr.contains { $0.contains("safe_sync_limit must be >= 0") })
    }

    @Test func syncReportsSafeSyncLimitExceededWithLimitAndActual() {
        let harness = RouterHarness()
        harness.syncService.runSyncError = SyncCoordinatorError.safeSyncLimitExceeded(limit: 100, actual: 101)

        let exitCode = harness.router.execute(arguments: ["sync"], io: harness.testIO)

        #expect(exitCode == 1)
        #expect(harness.testIO.stderr.contains { $0.contains("safe sync limit exceeded") })
        #expect(harness.testIO.stderr.contains { $0.contains("limit=100") })
        #expect(harness.testIO.stderr.contains { $0.contains("actual=101") })
    }
}

private final class RouterHarness {
    let configLoader = StubConfigLoader()
    let syncService = StubSyncService()
    let daemonControlBuilder = StubDaemonControlBuilder()
    let resetServiceBuilder = StubResetServiceBuilder()
    let logStoreBuilder = StubLogStoreBuilder()
    let testIO = TestIO()

    lazy var router = CLICommandRouter(
        configLoader: configLoader,
        syncService: syncService,
        daemonControlBuilder: daemonControlBuilder,
        resetServiceBuilder: resetServiceBuilder,
        logStoreBuilder: logStoreBuilder
    )
}
