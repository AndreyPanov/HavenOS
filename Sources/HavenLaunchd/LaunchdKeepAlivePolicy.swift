import Foundation

/// Models the `KeepAlive` key in a launchd property list.
///
/// launchd supports several keep-alive strategies. Haven uses a minimal
/// subset that maps cleanly to service management semantics:
///
/// - `always`: The job is restarted unconditionally whenever it exits.
///   Maps to `KeepAlive = true` in the plist.
/// - `successfulExit`: The job is restarted only when it exits with a
///   non-zero status. Maps to `KeepAlive = { SuccessfulExit = false }`.
/// - `none`: The job is not restarted. Maps to omitting `KeepAlive`
///   entirely (or setting it to `false`).
public enum LaunchdKeepAlivePolicy: Equatable, Sendable {

    /// Restart unconditionally whenever the process exits.
    case always

    /// Restart only when the process exits with a non-zero status.
    /// This is the most common policy for services that should stay running
    /// but shouldn't restart if they exit cleanly (e.g., graceful shutdown).
    case successfulExit

    /// Do not restart. The job runs once and stays stopped.
    case none

    /// Convert this policy to its plist-compatible representation.
    ///
    /// - `always` → `true` (Bool)
    /// - `successfulExit` → `{ "SuccessfulExit": false }` (Dict)
    /// - `none` → `false` (Bool)
    func plistValue() -> Any {
        switch self {
        case .always:
            return true
        case .successfulExit:
            return ["SuccessfulExit": false]
        case .none:
            return false
        }
    }

    /// Whether this policy should be included in the plist at all.
    /// When `none`, the key can be omitted entirely.
    var shouldIncludeInPlist: Bool {
        self != .none
    }
}
