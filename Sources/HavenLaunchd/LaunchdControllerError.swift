import Foundation

/// Errors from launchd controller operations.
///
/// These errors use service-oriented language. Raw launchctl output is
/// captured in the `detail` field for diagnostics but should not be
/// shown to end users.
public enum LaunchdControllerError: Error, LocalizedError, Equatable, Sendable {

    /// Failed to serialize the job definition to plist data.
    case plistSerializationFailed(label: String, detail: String)

    /// Failed to write the plist file to disk.
    case plistWriteFailed(label: String, path: String, detail: String)

    /// Failed to remove the plist file from disk.
    case plistRemoveFailed(label: String, path: String, detail: String)

    /// The bootstrap/load operation failed.
    case loadFailed(label: String, detail: String)

    /// The bootout/unload operation failed.
    case unloadFailed(label: String, detail: String)

    /// The start command failed.
    case startFailed(label: String, detail: String)

    /// The stop command failed.
    case stopFailed(label: String, detail: String)

    /// The status query failed.
    case statusQueryFailed(label: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .plistSerializationFailed(_, let detail):
            "Plist serialization failed: \(detail)"
        case .plistWriteFailed(_, _, let detail):
            "Plist write failed: \(detail)"
        case .plistRemoveFailed(_, _, let detail):
            "Plist remove failed: \(detail)"
        case .loadFailed(_, let detail):
            "Service load failed: \(detail)"
        case .unloadFailed(_, let detail):
            "Service unload failed: \(detail)"
        case .startFailed(_, let detail):
            "Service start failed: \(detail)"
        case .stopFailed(_, let detail):
            "Service stop failed: \(detail)"
        case .statusQueryFailed(_, let detail):
            "Status query failed: \(detail)"
        }
    }
}
