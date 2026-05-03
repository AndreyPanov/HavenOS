import XCTest
import Foundation
import HavenLaunchd
@testable import HavenExecutor

final class LaunchdServiceUpdateRuntimeControllerTests: XCTestCase {
    func testStopStartAndHealthcheckUseLaunchdLabel() async throws {
        let client = RecordingLaunchctlClient()
        client.results["print"] = LaunchctlResult(
            exitCode: 0,
            stdout: "pid = 42\nstate = running\n",
            stderr: ""
        )
        let launchd = LaunchdController(client: client)
        let runtime = LaunchdServiceUpdateRuntimeController(
            capabilityID: "capability",
            launchdController: launchd
        )

        try await runtime.stop(unitID: "unit")
        try await runtime.start(unitID: "unit")
        let healthy = try await runtime.healthcheck(unitID: "unit")

        XCTAssertTrue(healthy)
        XCTAssertEqual(client.calls, [
            "stop:app.haven.capability.unit",
            "start:app.haven.capability.unit",
            "print:app.haven.capability.unit",
        ])
    }

    func testHealthcheckReturnsFalseWhenLaunchdJobIsNotRunning() async throws {
        let client = RecordingLaunchctlClient()
        client.results["print"] = LaunchctlResult(
            exitCode: 0,
            stdout: "state = stopped\nlast exit code = 1\n",
            stderr: ""
        )
        let launchd = LaunchdController(client: client)
        let runtime = LaunchdServiceUpdateRuntimeController(
            capabilityID: "capability",
            launchdController: launchd
        )

        let healthy = try await runtime.healthcheck(unitID: "unit")

        XCTAssertFalse(healthy)
        XCTAssertEqual(client.calls, ["print:app.haven.capability.unit"])
    }
}

private final class RecordingLaunchctlClient: LaunchctlClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [String] = []
    var results: [String: LaunchctlResult] = [:]

    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func bootstrap(plistPath: String) throws -> LaunchctlResult {
        record("bootstrap:\(plistPath)")
    }

    func bootout(label: String) throws -> LaunchctlResult {
        record("bootout:\(label)")
    }

    func start(label: String) throws -> LaunchctlResult {
        record("start:\(label)")
    }

    func stop(label: String) throws -> LaunchctlResult {
        record("stop:\(label)")
    }

    func print(label: String) throws -> LaunchctlResult {
        record("print:\(label)")
    }

    private func record(_ call: String) -> LaunchctlResult {
        lock.lock()
        recordedCalls.append(call)
        let method = call.split(separator: ":", maxSplits: 1).first.map(String.init) ?? call
        let result = results[method] ?? LaunchctlResult(exitCode: 0, stdout: "", stderr: "")
        lock.unlock()
        return result
    }
}
