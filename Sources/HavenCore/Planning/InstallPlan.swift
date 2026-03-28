import Foundation

/// A deterministic, fully resolved plan for installing a capability.
///
/// The plan captures everything needed to set up a service — directories,
/// settings, ports, launch order — without actually executing anything.
/// Downstream layers (execution, launchd, UI) consume the plan.
public struct InstallPlan: Equatable, Sendable {
    /// The service being installed.
    public let service: PlannedService

    public init(service: PlannedService) {
        self.service = service
    }
}
