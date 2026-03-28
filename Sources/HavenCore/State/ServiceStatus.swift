import Foundation

/// The lifecycle status of an installed service.
public enum ServiceStatus: String, Codable, Equatable, Sendable {
    /// The service has been installed but is not running.
    case installed
    /// The service is currently running.
    case running
    /// The service was running but has been stopped.
    case stopped
    /// The service encountered an error.
    case failed
}
