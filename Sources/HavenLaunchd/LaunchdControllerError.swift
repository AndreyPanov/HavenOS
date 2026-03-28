import Foundation

/// Errors from launchd controller operations.
///
/// These errors use service-oriented language. Raw launchctl output is
/// captured in the `detail` field for diagnostics but should not be
/// shown to end users.
public enum LaunchdControllerError: Error, Equatable, Sendable {

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

    /// The job was expected to exist but was not found.
    case jobNotFound(label: String)
}
