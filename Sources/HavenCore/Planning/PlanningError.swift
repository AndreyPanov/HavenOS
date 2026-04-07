import Foundation

/// Errors thrown by the ``Planner`` when it cannot produce a valid plan.
public enum PlanningError: Error, LocalizedError, Equatable, Sendable {
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

    /// No available port could be found for a runtime unit (all ports exhausted).
    case noAvailablePorts(unitID: String)

    public var errorDescription: String? {
        switch self {
        case .capabilityNotFound(let id):
            "Capability '\(id)' not found."
        case .bundleNotFound(let id):
            "No bundle found for capability '\(id)'."
        case .runtimeUnitNotFound(let id, let bundleID):
            "Runtime unit '\(id)' referenced by bundle '\(bundleID)' not found."
        case .requiredSettingMissing(let key, let bundleID):
            "Required setting '\(key)' missing for bundle '\(bundleID)'."
        case .dependencyCycle(let ids):
            "Dependency cycle detected: \(ids.joined(separator: " → "))."
        case .noAvailablePorts(let unitID):
            "No available port found for runtime unit '\(unitID)'."
        }
    }
}
