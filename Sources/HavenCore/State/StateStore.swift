import Foundation

/// Persistent storage for Haven service state.
///
/// Implementations must be thread-safe. All mutations go through
/// this protocol so that the backing store can be swapped
/// (file-based, in-memory for tests, etc.).
public protocol StateStore: Sendable {

    /// Load the full state. Returns empty state if nothing is persisted yet.
    func load() throws -> HavenState

    /// Persist the full state, replacing whatever was stored before.
    func save(_ state: HavenState) throws

    /// Look up a single service by capability ID.
    /// Returns `nil` if no service with that ID is stored.
    func service(for capabilityID: String) throws -> StoredServiceState?

    /// Insert or update a service state. If a service with the same
    /// `capability` already exists, it is replaced.
    func upsert(_ service: StoredServiceState) throws

    /// Remove the service state for the given capability ID.
    /// Does nothing if no such service exists.
    func remove(capabilityID: String) throws
}
