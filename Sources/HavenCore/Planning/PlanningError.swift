import Foundation

/// Errors thrown by the ``Planner`` when it cannot produce a valid plan.
public enum PlanningError: Error, Equatable, Sendable {
    /// The requested capability ID does not exist in the registry.
    case capabilityNotFound(id: String)

    /// No bundle in the registry implements the requested capability.
    case bundleNotFound(capabilityID: String)

    /// A runtime unit referenced by the bundle is missing from the registry.
    case runtimeUnitNotFound(id: String, bundleID: String)

    /// A required setting was not supplied and has no default value.
    case requiredSettingMissing(key: String, bundleID: String)

    /// The runtime unit dependency graph contains a cycle.
    case dependencyCycle(unitIDs: [String])
}
