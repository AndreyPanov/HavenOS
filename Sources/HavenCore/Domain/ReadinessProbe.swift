import Foundation

/// Describes how to verify that a runtime unit is ready to accept connections
/// from dependent units during startup sequencing.
///
/// Unlike ``Healthcheck`` (ongoing liveness monitoring), a readiness probe
/// is used only during startup: the executor polls until the probe succeeds
/// before starting units that depend on this one.
public struct ReadinessProbe: Codable, Equatable, Sendable {

    /// Which strategy to use (reuses the same enum as ``Healthcheck``).
    public let type: Healthcheck.HealthcheckType

    /// Target for the check — a URL, host:port, or command string
    /// depending on `type`. Supports `${placeholder}` template expansion.
    public let target: String

    /// Maximum seconds to wait for the probe to succeed before failing.
    public let timeoutSeconds: Int

    /// Seconds between consecutive probe attempts.
    public let intervalSeconds: Int

    public init(
        type: Healthcheck.HealthcheckType,
        target: String,
        timeoutSeconds: Int = 30,
        intervalSeconds: Int = 2
    ) {
        self.type = type
        self.target = target
        self.timeoutSeconds = timeoutSeconds
        self.intervalSeconds = intervalSeconds
    }

    /// Validates that target is non-empty and numeric fields are positive.
    public func validate() throws {
        if target.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("ReadinessProbe target must not be empty.")
        }
        if timeoutSeconds <= 0 {
            throw ValidationError("ReadinessProbe timeoutSeconds must be positive.")
        }
        if intervalSeconds <= 0 {
            throw ValidationError("ReadinessProbe intervalSeconds must be positive.")
        }
    }
}
