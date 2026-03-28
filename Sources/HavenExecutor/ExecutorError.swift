import Foundation

/// Errors from service lifecycle operations.
///
/// All error cases use service-oriented language. Implementation details
/// such as launchctl, pip, brew, or PATH are never exposed in case names.
/// The `detail` field captures diagnostic information from lower layers.
public enum ExecutorError: Error, Equatable, Sendable {

    /// The service is already installed.
    case alreadyInstalled(capabilityID: String)

    /// The service is not installed.
    case notInstalled(capabilityID: String)

    /// Planning the installation failed.
    case planningFailed(capabilityID: String, detail: String)

    /// Runtime preparation failed for a unit.
    case preparationFailed(capabilityID: String, unitID: String, detail: String)

    /// Installing a service unit failed.
    case serviceInstallFailed(capabilityID: String, unitID: String, detail: String)

    /// Uninstalling a service unit failed.
    case serviceUninstallFailed(capabilityID: String, unitID: String, detail: String)

    /// Starting a service unit failed.
    case startFailed(capabilityID: String, unitID: String, detail: String)

    /// Stopping a service unit failed.
    case stopFailed(capabilityID: String, unitID: String, detail: String)

    /// Querying service status failed.
    case statusQueryFailed(capabilityID: String, detail: String)
}
