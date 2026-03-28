import Foundation

/// Deterministic label generation for launchd jobs.
///
/// Every launchd job requires a globally unique `Label` string. Haven uses
/// the convention:
///
/// ```
/// app.haven.<capability-id>.<unit-id>
/// ```
///
/// This ensures labels are predictable, collision-free, and easy to
/// identify in `launchctl list` output.
public enum LaunchdLabel {

    /// The prefix used for all Haven-managed launchd job labels.
    public static let prefix = "app.haven"

    /// Build a deterministic launchd label for a runtime unit.
    ///
    /// - Parameters:
    ///   - capabilityID: The capability this unit belongs to (e.g., `haven.capability.test-library`).
    ///   - unitID: The runtime unit identifier (e.g., `haven.unit.test-db`).
    /// - Returns: A label like `app.haven.haven.capability.test-library.haven.unit.test-db`.
    public static func label(capabilityID: String, unitID: String) -> String {
        "\(prefix).\(capabilityID).\(unitID)"
    }
}
