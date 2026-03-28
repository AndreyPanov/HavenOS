import Foundation

/// Persisted state for one installed service.
///
/// Captures everything needed to know what is installed, where it
/// lives on disk, and what settings/ports were resolved at install time.
public struct StoredServiceState: Codable, Equatable, Sendable {

    /// The capability this service provides.
    public let capabilityID: String

    /// The bundle that implements the capability.
    public let bundleID: String

    /// When this service was first installed.
    public let installedAt: Date

    /// When this service's state was last modified.
    public var updatedAt: Date

    /// Current lifecycle status.
    public var status: ServiceStatus

    /// Resolved settings at install time (key → value).
    public let resolvedSettings: [String: String]

    /// Port assignments per runtime unit.
    public let portAssignments: [StoredPortAssignment]

    /// IDs of the runtime units belonging to this service, in launch order.
    public let runtimeUnitIDs: [String]

    /// The directory layout for this service on disk.
    public let directoryLayout: ServiceDirectoryLayout

    public init(
        capabilityID: String,
        bundleID: String,
        installedAt: Date,
        updatedAt: Date,
        status: ServiceStatus,
        resolvedSettings: [String: String],
        portAssignments: [StoredPortAssignment],
        runtimeUnitIDs: [String],
        directoryLayout: ServiceDirectoryLayout
    ) {
        self.capabilityID = capabilityID
        self.bundleID = bundleID
        self.installedAt = installedAt
        self.updatedAt = updatedAt
        self.status = status
        self.resolvedSettings = resolvedSettings
        self.portAssignments = portAssignments
        self.runtimeUnitIDs = runtimeUnitIDs
        self.directoryLayout = directoryLayout
    }
}
