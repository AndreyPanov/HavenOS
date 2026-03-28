import Foundation

/// The top-level persisted state container.
///
/// Serialized as JSON to the state file. Contains all installed services
/// keyed by capability ID.
public struct HavenState: Codable, Equatable, Sendable {

    /// All installed services, keyed by capability ID.
    public var services: [String: StoredServiceState]

    public init(services: [String: StoredServiceState] = [:]) {
        self.services = services
    }
}
