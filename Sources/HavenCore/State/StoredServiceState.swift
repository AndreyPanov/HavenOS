import Foundation

/// Persisted state for one installed service.
///
/// Captures everything needed to know what is installed, where it
/// lives on disk, and what settings/ports were resolved at install time.
public struct StoredServiceState: Codable, Equatable, Sendable {

    /// The capability this service provides.
    public let capability: String

    /// The bundle that implements the capability.
    public let bundleID: String

    /// When this service was first installed.
    public let installedAt: Date

    /// When this service's state was last modified.
    public var updatedAt: Date

    /// Current lifecycle status.
    public var status: ServiceStatus

    /// Resolved settings (key → value). Updated when user changes paths post-install.
    public var resolvedSettings: [String: String]

    /// Port assignments per runtime unit.
    public let portAssignments: [StoredPortAssignment]

    /// IDs of the runtime units belonging to this service, in launch order.
    public let runtimeUnits: [String]

    /// The directory layout for this service on disk.
    public let directoryLayout: ServiceDirectoryLayout

    /// Metadata about installed artifacts, one per artifact-based runtime unit.
    /// Empty for services installed from local sources.
    public let artifactInfo: [StoredArtifactInfo]

    /// Metadata about installed Python environments, one per Python-based runtime unit.
    /// Empty for services with no Python units.
    public let pythonInfo: [StoredPythonInfo]

    /// Resolved onboarding steps from the install plan.
    /// Nil for services installed before onboarding was added.
    public let onboarding: Onboarding?

    /// Resolved readiness probes per runtime unit (unit ID → probe).
    /// Used during `start()` to wait for dependencies before launching dependents.
    public let readinessProbes: [String: ReadinessProbe]

    public init(
        capability: String,
        bundleID: String,
        installedAt: Date,
        updatedAt: Date,
        status: ServiceStatus,
        resolvedSettings: [String: String],
        portAssignments: [StoredPortAssignment],
        runtimeUnits: [String],
        directoryLayout: ServiceDirectoryLayout,
        artifactInfo: [StoredArtifactInfo] = [],
        pythonInfo: [StoredPythonInfo] = [],
        onboarding: Onboarding? = nil,
        readinessProbes: [String: ReadinessProbe] = [:]
    ) {
        self.capability = capability
        self.bundleID = bundleID
        self.installedAt = installedAt
        self.updatedAt = updatedAt
        self.status = status
        self.resolvedSettings = resolvedSettings
        self.portAssignments = portAssignments
        self.runtimeUnits = runtimeUnits
        self.directoryLayout = directoryLayout
        self.artifactInfo = artifactInfo
        self.pythonInfo = pythonInfo
        self.onboarding = onboarding
        self.readinessProbes = readinessProbes
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case capability, bundleID, installedAt, updatedAt, status
        case resolvedSettings, portAssignments, runtimeUnits
        case directoryLayout, artifactInfo, pythonInfo, onboarding, readinessProbes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        capability = try c.decode(String.self, forKey: .capability)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        installedAt = try c.decode(Date.self, forKey: .installedAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        status = try c.decode(ServiceStatus.self, forKey: .status)
        resolvedSettings = try c.decode([String: String].self, forKey: .resolvedSettings)
        portAssignments = try c.decode([StoredPortAssignment].self, forKey: .portAssignments)
        runtimeUnits = try c.decode([String].self, forKey: .runtimeUnits)
        directoryLayout = try c.decode(ServiceDirectoryLayout.self, forKey: .directoryLayout)
        artifactInfo = try c.decodeIfPresent([StoredArtifactInfo].self, forKey: .artifactInfo) ?? []
        pythonInfo = try c.decodeIfPresent([StoredPythonInfo].self, forKey: .pythonInfo) ?? []
        onboarding = try c.decodeIfPresent(Onboarding.self, forKey: .onboarding)
        readinessProbes = try c.decodeIfPresent([String: ReadinessProbe].self, forKey: .readinessProbes) ?? [:]
    }
}
