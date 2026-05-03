import Foundation
import HavenCore
import HavenInstaller
import HavenLaunchd

public struct LaunchdServiceUpdateRuntimeController: ServiceUpdateRuntimeController {
    private let capabilityID: String
    private let launchdController: LaunchdController
    private let readinessProbes: [String: ReadinessProbe]
    private let readinessChecker: ReadinessChecker

    public init(
        capabilityID: String,
        launchdController: LaunchdController,
        readinessProbes: [String: ReadinessProbe] = [:],
        readinessChecker: ReadinessChecker = ReadinessChecker()
    ) {
        self.capabilityID = capabilityID
        self.launchdController = launchdController
        self.readinessProbes = readinessProbes
        self.readinessChecker = readinessChecker
    }

    public func stop(unitID: String) async throws {
        try launchdController.stop(label: label(for: unitID))
    }

    public func start(unitID: String) async throws {
        try launchdController.start(label: label(for: unitID))
    }

    public func healthcheck(unitID: String) async throws -> Bool {
        if let probe = readinessProbes[unitID] {
            do {
                try await readinessChecker.waitUntilReady(probe: probe)
                return true
            } catch {
                return false
            }
        }

        let status = try launchdController.status(label: label(for: unitID))
        return status.state == .running
    }

    private func label(for unitID: String) -> String {
        LaunchdLabel.label(capabilityID: capabilityID, unitID: unitID)
    }
}
