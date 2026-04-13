import Foundation

/// A planned service: one capability implemented by one bundle
/// with its resolved runtime units, settings, and directory layout.
public struct PlannedService: Equatable, Sendable {
    /// The capability this service provides.
    public let capability: Capability

    /// The bundle implementing the capability.
    public let bundle: Bundle

    /// Runtime units in topological (dependency) order — dependencies first.
    public let units: [PlannedRuntimeUnit]

    /// Resolved settings: user overrides merged with defaults.
    public let resolvedSettings: [String: String]

    /// The directory layout for this service.
    public let directoryLayout: ServiceDirectoryLayout

    /// Resolved onboarding steps with all variables expanded.
    /// Nil if the bundle has no onboarding.
    public let resolvedOnboarding: Onboarding?

    /// Resolved provisions with variables expanded and conditions evaluated.
    /// Only includes provisions whose conditions are met.
    public let resolvedProvisions: [Provision]

    public init(
        capability: Capability,
        bundle: Bundle,
        units: [PlannedRuntimeUnit],
        resolvedSettings: [String: String],
        directoryLayout: ServiceDirectoryLayout,
        resolvedOnboarding: Onboarding? = nil,
        resolvedProvisions: [Provision] = []
    ) {
        self.capability = capability
        self.bundle = bundle
        self.units = units
        self.resolvedSettings = resolvedSettings
        self.directoryLayout = directoryLayout
        self.resolvedOnboarding = resolvedOnboarding
        self.resolvedProvisions = resolvedProvisions
    }
}
