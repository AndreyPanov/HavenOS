import Foundation

/// The contract that native capability UIs program against.
///
/// A facade presents a capability in user-facing terms (state, health, actions)
/// without exposing runtime units, launchd jobs, or other infrastructure.
///
/// Views read state and call `perform(_:)`. The facade delegates to a
/// ``BackendAdapter`` for backend-specific work.
@MainActor
public protocol CapabilityFacade: AnyObject, Observable {
    /// The capability ID this facade manages.
    var capabilityID: String { get }

    /// Current lifecycle state.
    var state: CapabilityState { get }

    /// Current health status.
    var health: CapabilityHealth { get }

    /// Actions available given the current state.
    var availableActions: [CapabilityAction] { get }

    /// URL for the backend's own web UI (nil if not applicable).
    var advancedURL: URL? { get }

    /// Execute an action. Throws if the action fails.
    func perform(_ action: CapabilityAction) async throws

    /// Refresh state from the underlying backend/store.
    func refresh()
}
