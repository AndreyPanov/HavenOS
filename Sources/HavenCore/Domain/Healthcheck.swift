import Foundation

/// Describes how to verify that a runtime unit is healthy.
public struct Healthcheck: Codable, Equatable, Sendable {

    /// The strategy used to check health.
    public enum HealthcheckType: String, Codable, Equatable, Sendable {
        /// Issue an HTTP GET and expect a 2xx response.
        case http
        /// Open a TCP connection and expect it to succeed.
        case tcp
        /// Run a shell command and expect exit code 0.
        case exec
    }

    /// Which strategy to use.
    public let type: HealthcheckType

    /// Target for the check — a URL, host:port, or command string
    /// depending on `type`.
    public let target: String

    /// Seconds between consecutive checks.
    public let intervalSeconds: Int

    /// Number of consecutive failures before the unit is marked unhealthy.
    public let retries: Int

    public init(
        type: HealthcheckType,
        target: String,
        intervalSeconds: Int = 30,
        retries: Int = 3
    ) {
        self.type = type
        self.target = target
        self.intervalSeconds = intervalSeconds
        self.retries = retries
    }

    /// Validates that target is non-empty and numeric fields are positive.
    public func validate() throws {
        if target.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Healthcheck target must not be empty.")
        }
        if intervalSeconds <= 0 {
            throw ValidationError("Healthcheck intervalSeconds must be positive.")
        }
        if retries <= 0 {
            throw ValidationError("Healthcheck retries must be positive.")
        }
    }
}
