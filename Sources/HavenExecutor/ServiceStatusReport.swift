import Foundation
import HavenCore
import HavenLaunchd

/// A snapshot of a service's runtime status.
///
/// Combines persisted state (from `StoredServiceState`) with live
/// per-unit status queried from launchd.
public struct ServiceStatusReport: Sendable {

    /// The capability this service provides.
    public let capability: String

    /// The bundle implementing this capability.
    public let bundleID: String

    /// The persisted lifecycle status.
    public let status: ServiceStatus

    /// Live status for each runtime unit.
    public let unitStatuses: [UnitStatusReport]

    public init(
        capability: String,
        bundleID: String,
        status: ServiceStatus,
        unitStatuses: [UnitStatusReport]
    ) {
        self.capability = capability
        self.bundleID = bundleID
        self.status = status
        self.unitStatuses = unitStatuses
    }
}

/// Live status of a single runtime unit as observed from launchd.
public struct UnitStatusReport: Sendable {

    /// The runtime unit identifier.
    public let unitID: String

    /// The launchd job label for this unit.
    public let launchdLabel: String

    /// The current state as reported by launchd.
    public let state: LaunchdJobStatus.State

    /// Process ID if the unit is currently running.
    public let pid: Int?

    /// Last exit code if available.
    public let lastExitStatus: Int?

    public init(
        unitID: String,
        launchdLabel: String,
        state: LaunchdJobStatus.State,
        pid: Int?,
        lastExitStatus: Int?
    ) {
        self.unitID = unitID
        self.launchdLabel = launchdLabel
        self.state = state
        self.pid = pid
        self.lastExitStatus = lastExitStatus
    }
}
