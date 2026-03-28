import XCTest
import Foundation
import HavenCore
import HavenRuntimes
@testable import HavenLaunchd

// MARK: - MockLaunchctlClient

/// A mock LaunchctlClient that records calls and returns canned results.
final class MockLaunchctlClient: LaunchctlClient, @unchecked Sendable {

    struct Call: Equatable {
        let method: String
        let arguments: [String]
    }

    private(set) var calls: [Call] = []

    /// Canned results keyed by method name. Falls back to a success result.
    var results: [String: LaunchctlResult] = [:]

    /// If set, the next call to this method will throw this error.
    var throwOnMethod: [String: Error] = [:]

    private let defaultSuccess = LaunchctlResult(exitCode: 0, stdout: "", stderr: "")

    func bootstrap(plistPath: String) throws -> LaunchctlResult {
        try record("bootstrap", arguments: [plistPath])
    }

    func bootout(label: String) throws -> LaunchctlResult {
        try record("bootout", arguments: [label])
    }

    func start(label: String) throws -> LaunchctlResult {
        try record("start", arguments: [label])
    }

    func stop(label: String) throws -> LaunchctlResult {
        try record("stop", arguments: [label])
    }

    func print(label: String) throws -> LaunchctlResult {
        try record("print", arguments: [label])
    }

    private func record(_ method: String, arguments: [String]) throws -> LaunchctlResult {
        calls.append(Call(method: method, arguments: arguments))
        if let error = throwOnMethod[method] {
            throw error
        }
        return results[method] ?? defaultSuccess
    }
}

// MARK: - LaunchdPaths Tests

final class LaunchdPathsTests: XCTestCase {

    func testDefaultLaunchAgentsDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let expected = home.appendingPathComponent("Library").appendingPathComponent("LaunchAgents")
        XCTAssertEqual(LaunchdPaths.defaultLaunchAgentsDirectory, expected)
    }

    func testCustomLaunchAgentsDirectory() {
        let custom = URL(fileURLWithPath: "/tmp/test-agents")
        let paths = LaunchdPaths(launchAgentsDirectory: custom)
        XCTAssertEqual(paths.launchAgentsDirectory, custom)
    }

    func testPlistPathForLabel() {
        let paths = LaunchdPaths(launchAgentsDirectory: URL(fileURLWithPath: "/tmp/agents"))
        let plistPath = paths.plistPath(for: "app.haven.cap.x.unit.y")
        XCTAssertEqual(plistPath.path, "/tmp/agents/app.haven.cap.x.unit.y.plist")
    }

    func testPlistPathIsDeterministic() {
        let paths = LaunchdPaths(launchAgentsDirectory: URL(fileURLWithPath: "/tmp/agents"))
        let a = paths.plistPath(for: "app.haven.cap.x.unit.y")
        let b = paths.plistPath(for: "app.haven.cap.x.unit.y")
        XCTAssertEqual(a, b)
    }

    func testDifferentLabelsProduceDifferentPaths() {
        let paths = LaunchdPaths(launchAgentsDirectory: URL(fileURLWithPath: "/tmp/agents"))
        let a = paths.plistPath(for: "app.haven.cap.x.unit.a")
        let b = paths.plistPath(for: "app.haven.cap.x.unit.b")
        XCTAssertNotEqual(a, b)
    }

    func testPlistPathEndsWithPlistExtension() {
        let paths = LaunchdPaths(launchAgentsDirectory: URL(fileURLWithPath: "/tmp/agents"))
        let plistPath = paths.plistPath(for: "app.haven.cap.x.unit.y")
        XCTAssertEqual(plistPath.pathExtension, "plist")
    }

    func testEquality() {
        let a = LaunchdPaths(launchAgentsDirectory: URL(fileURLWithPath: "/tmp/agents"))
        let b = LaunchdPaths(launchAgentsDirectory: URL(fileURLWithPath: "/tmp/agents"))
        XCTAssertEqual(a, b)
    }
}

// MARK: - LaunchdJobStatus Tests

final class LaunchdJobStatusTests: XCTestCase {

    func testRunningStatus() {
        let status = LaunchdJobStatus(
            state: .running,
            pid: 12345,
            lastExitStatus: nil,
            label: "app.haven.cap.unit"
        )
        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.pid, 12345)
        XCTAssertNil(status.lastExitStatus)
    }

    func testStoppedStatus() {
        let status = LaunchdJobStatus(
            state: .stopped,
            pid: nil,
            lastExitStatus: 0,
            label: "app.haven.cap.unit"
        )
        XCTAssertEqual(status.state, .stopped)
        XCTAssertNil(status.pid)
        XCTAssertEqual(status.lastExitStatus, 0)
    }

    func testInstalledStatus() {
        let status = LaunchdJobStatus(state: .installed, label: "app.haven.cap.unit")
        XCTAssertEqual(status.state, .installed)
        XCTAssertNil(status.pid)
        XCTAssertNil(status.lastExitStatus)
    }

    func testNotFoundStatus() {
        let status = LaunchdJobStatus(state: .notFound, label: "app.haven.cap.unit")
        XCTAssertEqual(status.state, .notFound)
    }

    func testEquality() {
        let a = LaunchdJobStatus(state: .running, pid: 100, label: "x")
        let b = LaunchdJobStatus(state: .running, pid: 100, label: "x")
        XCTAssertEqual(a, b)
    }

    func testInequality() {
        let a = LaunchdJobStatus(state: .running, pid: 100, label: "x")
        let b = LaunchdJobStatus(state: .stopped, pid: nil, label: "x")
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - LaunchdControllerError Tests

final class LaunchdControllerErrorTests: XCTestCase {

    func testEquality() {
        let a = LaunchdControllerError.loadFailed(label: "x", detail: "d")
        let b = LaunchdControllerError.loadFailed(label: "x", detail: "d")
        XCTAssertEqual(a, b)
    }

    func testInequality() {
        let a = LaunchdControllerError.loadFailed(label: "x", detail: "d")
        let b = LaunchdControllerError.unloadFailed(label: "x", detail: "d")
        XCTAssertNotEqual(a, b)
    }

    func testNoToolingLeaksInErrorCases() {
        let errors: [LaunchdControllerError] = [
            .plistSerializationFailed(label: "l", detail: "d"),
            .plistWriteFailed(label: "l", path: "/p", detail: "d"),
            .plistRemoveFailed(label: "l", path: "/p", detail: "d"),
            .loadFailed(label: "l", detail: "d"),
            .unloadFailed(label: "l", detail: "d"),
            .startFailed(label: "l", detail: "d"),
            .stopFailed(label: "l", detail: "d"),
            .statusQueryFailed(label: "l", detail: "d"),
            .jobNotFound(label: "l"),
        ]
        let forbidden = ["launchctl", "bootstrap", "bootout", "kickstart"]

        for error in errors {
            let description = String(describing: error)
            let casePrefix = description.prefix(while: { $0 != "(" })
            for word in forbidden {
                XCTAssertFalse(
                    casePrefix.contains(word),
                    "Error case name should not contain '\(word)': \(casePrefix)"
                )
            }
        }
    }
}

// MARK: - LaunchctlResult Tests

final class LaunchctlResultTests: XCTestCase {

    func testSucceeded() {
        let result = LaunchctlResult(exitCode: 0, stdout: "", stderr: "")
        XCTAssertTrue(result.succeeded)
    }

    func testFailed() {
        let result = LaunchctlResult(exitCode: 1, stdout: "", stderr: "error")
        XCTAssertFalse(result.succeeded)
    }

    func testEquality() {
        let a = LaunchctlResult(exitCode: 0, stdout: "ok", stderr: "")
        let b = LaunchctlResult(exitCode: 0, stdout: "ok", stderr: "")
        XCTAssertEqual(a, b)
    }
}

// MARK: - LaunchdController Install Tests

final class LaunchdControllerInstallTests: XCTestCase {

    private var tempDir: URL!
    private var mock: MockLaunchctlClient!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-ctrl-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mock = MockLaunchctlClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInstallWritesPlistFile() throws {
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)
        let job = makeTestJob(label: "app.haven.cap.x.unit.y")

        try controller.install(job: job)

        let plistURL = tempDir.appendingPathComponent("app.haven.cap.x.unit.y.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
    }

    func testInstallWritesValidPlist() throws {
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)
        let job = makeTestJob(label: "app.haven.cap.x.unit.y")

        try controller.install(job: job)

        let plistURL = tempDir.appendingPathComponent("app.haven.cap.x.unit.y.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any]

        XCTAssertNotNil(plist)
        XCTAssertEqual(plist?["Label"] as? String, "app.haven.cap.x.unit.y")
        XCTAssertEqual(plist?["ProgramArguments"] as? [String], ["/bin/x", "--flag"])
        XCTAssertEqual(plist?["RunAtLoad"] as? Bool, true)
    }

    func testInstallCallsBootstrap() throws {
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)
        let job = makeTestJob(label: "app.haven.cap.x.unit.y")

        try controller.install(job: job)

        XCTAssertEqual(mock.calls.count, 1)
        XCTAssertEqual(mock.calls[0].method, "bootstrap")
        let expectedPlistPath = tempDir.appendingPathComponent("app.haven.cap.x.unit.y.plist").path
        XCTAssertEqual(mock.calls[0].arguments, [expectedPlistPath])
    }

    func testInstallThrowsOnBootstrapFailure() {
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        mock.results["bootstrap"] = LaunchctlResult(
            exitCode: 1, stdout: "", stderr: "already loaded"
        )
        let controller = LaunchdController(paths: paths, client: mock)
        let job = makeTestJob(label: "app.haven.cap.x.unit.y")

        XCTAssertThrowsError(try controller.install(job: job)) { error in
            guard case .loadFailed(let label, _) = error as? LaunchdControllerError else {
                XCTFail("Expected loadFailed, got \(error)")
                return
            }
            XCTAssertEqual(label, "app.haven.cap.x.unit.y")
        }
    }

    func testInstallThrowsWhenClientThrows() {
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        mock.throwOnMethod["bootstrap"] = NSError(domain: "test", code: 42)
        let controller = LaunchdController(paths: paths, client: mock)
        let job = makeTestJob(label: "app.haven.cap.x.unit.y")

        XCTAssertThrowsError(try controller.install(job: job)) { error in
            guard case .loadFailed = error as? LaunchdControllerError else {
                XCTFail("Expected loadFailed, got \(error)")
                return
            }
        }
    }
}

// MARK: - LaunchdController Uninstall Tests

final class LaunchdControllerUninstallTests: XCTestCase {

    private var tempDir: URL!
    private var mock: MockLaunchctlClient!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-ctrl-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mock = MockLaunchctlClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testUninstallCallsBootout() throws {
        // Pre-create a plist file so uninstall can remove it
        let plistURL = tempDir.appendingPathComponent("app.haven.cap.x.unit.y.plist")
        try Data("test".utf8).write(to: plistURL)

        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        try controller.uninstall(label: "app.haven.cap.x.unit.y")

        XCTAssertEqual(mock.calls.count, 1)
        XCTAssertEqual(mock.calls[0].method, "bootout")
        XCTAssertEqual(mock.calls[0].arguments, ["app.haven.cap.x.unit.y"])
    }

    func testUninstallRemovesPlistFile() throws {
        let plistURL = tempDir.appendingPathComponent("app.haven.cap.x.unit.y.plist")
        try Data("test".utf8).write(to: plistURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))

        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        try controller.uninstall(label: "app.haven.cap.x.unit.y")

        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
    }

    func testUninstallToleratesMissingPlistFile() throws {
        // No plist file exists — should not throw on the remove step
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        XCTAssertNoThrow(try controller.uninstall(label: "app.haven.cap.x.unit.y"))
    }

    func testUninstallThrowsOnBootoutFailure() {
        mock.results["bootout"] = LaunchctlResult(
            exitCode: 1, stdout: "", stderr: "not found"
        )
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        XCTAssertThrowsError(try controller.uninstall(label: "app.haven.cap.x.unit.y")) { error in
            guard case .unloadFailed(let label, _) = error as? LaunchdControllerError else {
                XCTFail("Expected unloadFailed, got \(error)")
                return
            }
            XCTAssertEqual(label, "app.haven.cap.x.unit.y")
        }
    }
}

// MARK: - LaunchdController Start/Stop Tests

final class LaunchdControllerStartStopTests: XCTestCase {

    private var tempDir: URL!
    private var mock: MockLaunchctlClient!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-ctrl-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mock = MockLaunchctlClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testStartCallsClient() throws {
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        try controller.start(label: "app.haven.cap.x.unit.y")

        XCTAssertEqual(mock.calls.count, 1)
        XCTAssertEqual(mock.calls[0].method, "start")
        XCTAssertEqual(mock.calls[0].arguments, ["app.haven.cap.x.unit.y"])
    }

    func testStopCallsClient() throws {
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        try controller.stop(label: "app.haven.cap.x.unit.y")

        XCTAssertEqual(mock.calls.count, 1)
        XCTAssertEqual(mock.calls[0].method, "stop")
        XCTAssertEqual(mock.calls[0].arguments, ["app.haven.cap.x.unit.y"])
    }

    func testStartThrowsOnFailure() {
        mock.results["start"] = LaunchctlResult(
            exitCode: 3, stdout: "", stderr: "no such process"
        )
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        XCTAssertThrowsError(try controller.start(label: "label.x")) { error in
            guard case .startFailed = error as? LaunchdControllerError else {
                XCTFail("Expected startFailed, got \(error)")
                return
            }
        }
    }

    func testStopThrowsOnFailure() {
        mock.results["stop"] = LaunchctlResult(
            exitCode: 3, stdout: "", stderr: "no such process"
        )
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        XCTAssertThrowsError(try controller.stop(label: "label.x")) { error in
            guard case .stopFailed = error as? LaunchdControllerError else {
                XCTFail("Expected stopFailed, got \(error)")
                return
            }
        }
    }

    func testStartThrowsWhenClientThrows() {
        mock.throwOnMethod["start"] = NSError(domain: "test", code: 1)
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        XCTAssertThrowsError(try controller.start(label: "label.x")) { error in
            guard case .startFailed = error as? LaunchdControllerError else {
                XCTFail("Expected startFailed, got \(error)")
                return
            }
        }
    }

    func testStopThrowsWhenClientThrows() {
        mock.throwOnMethod["stop"] = NSError(domain: "test", code: 1)
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        XCTAssertThrowsError(try controller.stop(label: "label.x")) { error in
            guard case .stopFailed = error as? LaunchdControllerError else {
                XCTFail("Expected stopFailed, got \(error)")
                return
            }
        }
    }
}

// MARK: - LaunchdController Status Tests

final class LaunchdControllerStatusTests: XCTestCase {

    private var tempDir: URL!
    private var mock: MockLaunchctlClient!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-ctrl-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mock = MockLaunchctlClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testStatusRunning() throws {
        mock.results["print"] = LaunchctlResult(
            exitCode: 0,
            stdout: """
            app.haven.cap.x.unit.y = {
                pid = 12345
                state = running
                last exit code = 0
            }
            """,
            stderr: ""
        )
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        let status = try controller.status(label: "app.haven.cap.x.unit.y")

        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.pid, 12345)
        XCTAssertEqual(status.lastExitStatus, 0)
        XCTAssertEqual(status.label, "app.haven.cap.x.unit.y")
    }

    func testStatusStopped() throws {
        mock.results["print"] = LaunchctlResult(
            exitCode: 0,
            stdout: """
            app.haven.cap.x.unit.y = {
                state = waiting
                last exit code = 1
            }
            """,
            stderr: ""
        )
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        let status = try controller.status(label: "app.haven.cap.x.unit.y")

        XCTAssertEqual(status.state, .stopped)
        XCTAssertNil(status.pid)
        XCTAssertEqual(status.lastExitStatus, 1)
    }

    func testStatusInstalledWhenPlistExistsButNotLoaded() throws {
        // Create the plist file to simulate "installed but not loaded"
        let plistURL = tempDir.appendingPathComponent("app.haven.cap.x.unit.y.plist")
        try Data("test".utf8).write(to: plistURL)

        mock.results["print"] = LaunchctlResult(
            exitCode: 113, stdout: "", stderr: "Could not find service"
        )
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        let status = try controller.status(label: "app.haven.cap.x.unit.y")

        XCTAssertEqual(status.state, .installed)
    }

    func testStatusNotFoundWhenNoPlistAndNotLoaded() throws {
        mock.results["print"] = LaunchctlResult(
            exitCode: 113, stdout: "", stderr: "Could not find service"
        )
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        let status = try controller.status(label: "app.haven.cap.x.unit.y")

        XCTAssertEqual(status.state, .notFound)
    }

    func testStatusCallsPrint() throws {
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        _ = try controller.status(label: "app.haven.cap.x.unit.y")

        XCTAssertEqual(mock.calls.count, 1)
        XCTAssertEqual(mock.calls[0].method, "print")
        XCTAssertEqual(mock.calls[0].arguments, ["app.haven.cap.x.unit.y"])
    }

    func testStatusThrowsWhenClientThrows() {
        mock.throwOnMethod["print"] = NSError(domain: "test", code: 1)
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)

        XCTAssertThrowsError(try controller.status(label: "label.x")) { error in
            guard case .statusQueryFailed = error as? LaunchdControllerError else {
                XCTFail("Expected statusQueryFailed, got \(error)")
                return
            }
        }
    }
}

// MARK: - Status Parsing Tests

final class LaunchdStatusParsingTests: XCTestCase {

    func testParseRunningWithPID() {
        let output = """
        app.haven.cap.x.unit.y = {
            pid = 42
            state = running
            last exit code = 0
        }
        """
        let status = LaunchdController.parseStatus(label: "test", output: output)
        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.pid, 42)
        XCTAssertEqual(status.lastExitStatus, 0)
    }

    func testParseStoppedNoProcess() {
        let output = """
        app.haven.cap.x.unit.y = {
            state = waiting
            last exit code = 127
        }
        """
        let status = LaunchdController.parseStatus(label: "test", output: output)
        XCTAssertEqual(status.state, .stopped)
        XCTAssertNil(status.pid)
        XCTAssertEqual(status.lastExitStatus, 127)
    }

    func testParsePIDOverridesStateLine() {
        // If a PID exists, the job is running regardless of the state line
        let output = """
        pid = 999
        state = not-running
        """
        let status = LaunchdController.parseStatus(label: "test", output: output)
        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.pid, 999)
    }

    func testParseEmptyOutput() {
        let status = LaunchdController.parseStatus(label: "test", output: "")
        XCTAssertEqual(status.state, .stopped)
        XCTAssertNil(status.pid)
        XCTAssertNil(status.lastExitStatus)
    }

    func testParseOutputWithExtraWhitespace() {
        let output = """
            pid = 100
            last exit code = 0
            state = running
        """
        let status = LaunchdController.parseStatus(label: "test", output: output)
        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.pid, 100)
        XCTAssertEqual(status.lastExitStatus, 0)
    }

    func testParseLabelIsPreserved() {
        let status = LaunchdController.parseStatus(label: "app.haven.my.label", output: "")
        XCTAssertEqual(status.label, "app.haven.my.label")
    }
}

// MARK: - Integration: Install then Uninstall

final class LaunchdControllerIntegrationTests: XCTestCase {

    private var tempDir: URL!
    private var mock: MockLaunchctlClient!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-ctrl-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mock = MockLaunchctlClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInstallThenUninstall() throws {
        let paths = LaunchdPaths(launchAgentsDirectory: tempDir)
        let controller = LaunchdController(paths: paths, client: mock)
        let job = makeTestJob(label: "app.haven.cap.x.unit.y")
        let plistURL = tempDir.appendingPathComponent("app.haven.cap.x.unit.y.plist")

        // Install
        try controller.install(job: job)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertEqual(mock.calls.count, 1)
        XCTAssertEqual(mock.calls[0].method, "bootstrap")

        // Uninstall
        try controller.uninstall(label: "app.haven.cap.x.unit.y")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertEqual(mock.calls.count, 2)
        XCTAssertEqual(mock.calls[1].method, "bootout")
    }

    func testInstallCreatesLaunchAgentsDirectoryIfNeeded() throws {
        let nestedDir = tempDir.appendingPathComponent("nested").appendingPathComponent("agents")
        let paths = LaunchdPaths(launchAgentsDirectory: nestedDir)
        let controller = LaunchdController(paths: paths, client: mock)
        let job = makeTestJob(label: "app.haven.cap.x.unit.y")

        try controller.install(job: job)

        let plistURL = nestedDir.appendingPathComponent("app.haven.cap.x.unit.y.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
    }
}

// MARK: - ProcessLaunchctlClient Tests

final class ProcessLaunchctlClientTests: XCTestCase {

    func testDomainTarget() {
        let client = ProcessLaunchctlClient()
        let uid = getuid()
        XCTAssertEqual(client.domainTarget, "gui/\(uid)")
    }

    func testServiceTarget() {
        let client = ProcessLaunchctlClient()
        let uid = getuid()
        let target = client.serviceTarget(label: "app.haven.cap.unit")
        XCTAssertEqual(target, "gui/\(uid)/app.haven.cap.unit")
    }
}

// MARK: - Test Helpers

private func makeTestJob(label: String) -> LaunchdJob {
    LaunchdJob(
        label: label,
        programArguments: ["/bin/x", "--flag"],
        environmentVariables: ["KEY": "val"],
        workingDirectory: "/tmp",
        standardOutPath: "/tmp/stdout.log",
        standardErrorPath: "/tmp/stderr.log",
        runAtLoad: true,
        keepAlive: .successfulExit
    )
}
