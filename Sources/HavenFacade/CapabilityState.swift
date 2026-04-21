/// Lifecycle state of a capability as seen by the UI.
public enum CapabilityState: Sendable, Equatable {
    /// Installed but not running.
    case idle
    /// Currently starting up.
    case starting
    /// Running and healthy.
    case ready
    /// Running but experiencing issues.
    case degraded(String)
    /// Failed to start or crashed.
    case error(String)
}
