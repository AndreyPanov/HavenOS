import XCTest
import Foundation
import HavenCore
@testable import HavenInstaller

final class ServiceUpdateManagerTests: XCTestCase {

    func testSuccessfulUpdateRunsSafeSequence() async {
        let candidate = makeCandidate()
        let artifacts = RecordingArtifactPipeline()
        let runtime = RecordingRuntimeController()
        let manager = ServiceUpdateManager(
            artifactPipeline: artifacts,
            runtimeController: runtime
        )

        let result = await manager.apply(candidate)
        let artifactCalls = await artifacts.calls()
        let runtimeCalls = await runtime.calls()
        let stateHistory = await manager.stateHistory()

        XCTAssertEqual(result, .completed(candidate))
        XCTAssertEqual(artifactCalls, ["download", "validate", "promote", "finalize"])
        XCTAssertEqual(runtimeCalls, ["stop:unit", "start:unit", "healthcheck:unit"])
        XCTAssertEqual(stateHistory, [
            .idle,
            .downloading(progress: nil),
            .validating,
            .stopping,
            .replacing,
            .restarting,
            .healthchecking,
            .completed(candidate),
        ])
    }

    func testHealthcheckFailureRollsBackReplacementAndRestartsOldService() async {
        let candidate = makeCandidate()
        let artifacts = RecordingArtifactPipeline()
        let runtime = RecordingRuntimeController(healthcheckResult: false)
        let manager = ServiceUpdateManager(
            artifactPipeline: artifacts,
            runtimeController: runtime
        )

        let result = await manager.apply(candidate)
        let artifactCalls = await artifacts.calls()
        let runtimeCalls = await runtime.calls()
        let stateHistory = await manager.stateHistory()

        guard case .rolledBack(let reason) = result else {
            return XCTFail("Expected rollback")
        }
        XCTAssertTrue(reason.contains("Healthcheck failed"))
        XCTAssertEqual(artifactCalls, ["download", "validate", "promote", "rollback"])
        XCTAssertEqual(runtimeCalls, [
            "stop:unit",
            "start:unit",
            "healthcheck:unit",
            "stop:unit",
            "start:unit",
        ])
        XCTAssertTrue(stateHistory.contains(.rollingBack))
    }

    func testPromoteFailureRestartsOldServiceWithoutArtifactRollbackToken() async {
        let candidate = makeCandidate()
        let artifacts = RecordingArtifactPipeline(failAt: .promote)
        let runtime = RecordingRuntimeController()
        let manager = ServiceUpdateManager(
            artifactPipeline: artifacts,
            runtimeController: runtime
        )

        let result = await manager.apply(candidate)
        let artifactCalls = await artifacts.calls()
        let runtimeCalls = await runtime.calls()

        guard case .rolledBack(let reason) = result else {
            return XCTFail("Expected rollback")
        }
        XCTAssertTrue(reason.contains("Injected promote failure"))
        XCTAssertEqual(artifactCalls, ["download", "validate", "promote"])
        XCTAssertEqual(runtimeCalls, ["stop:unit", "start:unit"])
    }

    func testSuccessfulUpdateCommitsMetadataAfterHealthcheck() async {
        let candidate = makeCandidate()
        let artifacts = RecordingArtifactPipeline()
        let runtime = RecordingRuntimeController()
        let metadata = RecordingStateTransaction()
        let manager = ServiceUpdateManager(
            artifactPipeline: artifacts,
            runtimeController: runtime,
            stateTransaction: metadata
        )

        let result = await manager.apply(candidate)
        let metadataCalls = await metadata.calls()

        XCTAssertEqual(result, .completed(candidate))
        XCTAssertEqual(metadataCalls, ["commit:unit"])
    }

    func testMetadataCommitFailureRollsBackReplacementAndRestartsOldService() async {
        let candidate = makeCandidate()
        let artifacts = RecordingArtifactPipeline()
        let runtime = RecordingRuntimeController()
        let metadata = RecordingStateTransaction(failCommit: true)
        let manager = ServiceUpdateManager(
            artifactPipeline: artifacts,
            runtimeController: runtime,
            stateTransaction: metadata
        )

        let result = await manager.apply(candidate)
        let artifactCalls = await artifacts.calls()
        let runtimeCalls = await runtime.calls()
        let metadataCalls = await metadata.calls()

        guard case .rolledBack(let reason) = result else {
            return XCTFail("Expected rollback")
        }
        XCTAssertTrue(reason.contains("Injected metadata failure"))
        XCTAssertEqual(artifactCalls, ["download", "validate", "promote", "rollback"])
        XCTAssertEqual(runtimeCalls, [
            "stop:unit",
            "start:unit",
            "healthcheck:unit",
            "stop:unit",
            "start:unit",
        ])
        XCTAssertEqual(metadataCalls, ["commit:unit"])
    }

    private func makeCandidate() -> UpdateCandidate {
        UpdateCandidate(
            unitID: "unit",
            repo: "owner/app",
            currentVersion: "v1.0.0",
            latestVersion: "v1.1.0"
        )
    }
}

private enum InjectedFailure: Error, LocalizedError {
    case download
    case validate
    case promote
    case stop
    case start

    var errorDescription: String? {
        switch self {
        case .download: "Injected download failure"
        case .validate: "Injected validate failure"
        case .promote: "Injected promote failure"
        case .stop: "Injected stop failure"
        case .start: "Injected start failure"
        }
    }
}

private actor RecordingArtifactPipeline: ServiceUpdateArtifactPipeline {
    private let failAt: InjectedFailure?
    private var recordedCalls: [String] = []

    init(failAt: InjectedFailure? = nil) {
        self.failAt = failAt
    }

    func download(_ candidate: UpdateCandidate) async throws -> PreparedServiceUpdate {
        recordedCalls.append("download")
        if failAt == .download { throw InjectedFailure.download }
        return PreparedServiceUpdate(candidate: candidate)
    }

    func validate(_ prepared: PreparedServiceUpdate) async throws {
        recordedCalls.append("validate")
        if failAt == .validate { throw InjectedFailure.validate }
    }

    func promote(_ prepared: PreparedServiceUpdate) async throws -> ServiceUpdateRollbackToken {
        recordedCalls.append("promote")
        if failAt == .promote { throw InjectedFailure.promote }
        return ServiceUpdateRollbackToken(candidate: prepared.candidate)
    }

    func rollback(_ token: ServiceUpdateRollbackToken) async throws {
        recordedCalls.append("rollback")
    }

    func finalize(_ token: ServiceUpdateRollbackToken) async throws {
        recordedCalls.append("finalize")
    }

    func calls() -> [String] {
        recordedCalls
    }
}

private actor RecordingRuntimeController: ServiceUpdateRuntimeController {
    private let healthcheckResult: Bool
    private let failAt: InjectedFailure?
    private var recordedCalls: [String] = []

    init(healthcheckResult: Bool = true, failAt: InjectedFailure? = nil) {
        self.healthcheckResult = healthcheckResult
        self.failAt = failAt
    }

    func stop(unitID: String) async throws {
        recordedCalls.append("stop:\(unitID)")
        if failAt == .stop { throw InjectedFailure.stop }
    }

    func start(unitID: String) async throws {
        recordedCalls.append("start:\(unitID)")
        if failAt == .start { throw InjectedFailure.start }
    }

    func healthcheck(unitID: String) async throws -> Bool {
        recordedCalls.append("healthcheck:\(unitID)")
        return healthcheckResult
    }

    func calls() -> [String] {
        recordedCalls
    }
}

private enum InjectedMetadataFailure: Error, LocalizedError {
    case commit

    var errorDescription: String? {
        "Injected metadata failure"
    }
}

private actor RecordingStateTransaction: ServiceUpdateStateTransaction {
    private let failCommit: Bool
    private var recordedCalls: [String] = []

    init(failCommit: Bool = false) {
        self.failCommit = failCommit
    }

    func commit(
        _ candidate: UpdateCandidate,
        replacementInstallDirectory: URL?
    ) async throws -> ServiceUpdateStateRollbackToken {
        recordedCalls.append("commit:\(candidate.unitID)")
        if failCommit { throw InjectedMetadataFailure.commit }
        return ServiceUpdateStateRollbackToken(previousService: StoredServiceState(
            capability: "capability",
            bundleID: "bundle",
            installedAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            status: .running,
            resolvedSettings: [:],
            portAssignments: [],
            runtimeUnits: [candidate.unitID],
            directoryLayout: ServiceDirectoryLayout(
                baseDirectory: URL(fileURLWithPath: "/tmp/haven-test"),
                capabilityID: "capability"
            )
        ))
    }

    func rollback(_ token: ServiceUpdateStateRollbackToken) async throws {
        recordedCalls.append("metadataRollback")
    }

    func calls() -> [String] {
        recordedCalls
    }
}
