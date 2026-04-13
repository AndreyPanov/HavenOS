import Foundation

/// Errors from service lifecycle operations.
///
/// All error cases use service-oriented language. Implementation details
/// such as launchctl, pip, brew, or PATH are never exposed in case names.
/// The `detail` field captures diagnostic information from lower layers.
public enum ExecutorError: Error, LocalizedError, Equatable, Sendable {

    /// The service is already installed.
    case alreadyInstalled(capabilityID: String)

    /// The service is not installed.
    case notInstalled(capabilityID: String)

    /// Planning the installation failed.
    case planningFailed(capabilityID: String, detail: String)

    /// A runtime type is not yet supported in the executor.
    case unsupportedRuntime(capabilityID: String, unitID: String, detail: String)

    /// Installing a service artifact failed.
    case artifactInstallFailed(capabilityID: String, unitID: String, detail: String)

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

    /// Provisioning a file during installation failed.
    case provisioningFailed(capabilityID: String, detail: String)

    /// Querying service status failed.
    case statusQueryFailed(capabilityID: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .alreadyInstalled(let id):
            "Service '\(id)' is already installed."
        case .notInstalled(let id):
            "Service '\(id)' is not installed."
        case .planningFailed(_, let detail):
            "Planning failed: \(detail)"
        case .unsupportedRuntime(_, _, let detail):
            detail
        case .artifactInstallFailed(_, _, let detail):
            "Artifact install failed: \(detail)"
        case .preparationFailed(_, _, let detail):
            "Preparation failed: \(detail)"
        case .serviceInstallFailed(_, _, let detail):
            "Service install failed: \(detail)"
        case .serviceUninstallFailed(_, _, let detail):
            "Uninstall failed: \(detail)"
        case .startFailed(_, _, let detail):
            "Start failed: \(detail)"
        case .stopFailed(_, _, let detail):
            "Stop failed: \(detail)"
        case .provisioningFailed(_, let detail):
            "Provisioning failed: \(detail)"
        case .statusQueryFailed(_, let detail):
            "Status query failed: \(detail)"
        }
    }
}
