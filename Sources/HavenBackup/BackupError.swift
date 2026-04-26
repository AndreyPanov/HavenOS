import Foundation

/// Errors that can occur during backup or restore operations.
public enum BackupError: Error, Sendable, Equatable {
    /// The backup destination path has not been configured.
    case notConfigured

    /// The backup destination is not reachable (e.g. unmounted NAS).
    case destinationUnreachable(path: String)

    /// Not enough disk space at the destination.
    case insufficientSpace(needed: UInt64, available: UInt64)

    /// A file operation failed for a specific capability.
    case capabilityBackupFailed(capabilityID: String, reason: String)

    /// The manifest file is missing or unreadable at the restore source.
    case manifestNotFound(path: String)

    /// The manifest version is newer than this Haven version supports.
    case unsupportedManifestVersion(found: Int, supported: Int)

    /// A general I/O error.
    case ioError(String)
}

extension BackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Backup destination has not been configured."
        case .destinationUnreachable(let path):
            "Backup destination is not available: \(path)"
        case .insufficientSpace(let needed, let available):
            "Not enough disk space. Need \(ByteCountFormatter.string(fromByteCount: Int64(needed), countStyle: .file)), have \(ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file))."
        case .capabilityBackupFailed(let id, let reason):
            "Failed to back up \(id): \(reason)"
        case .manifestNotFound(let path):
            "No backup found at \(path)"
        case .unsupportedManifestVersion(let found, let supported):
            "Backup was created by a newer Haven version (format \(found), supported up to \(supported))."
        case .ioError(let message):
            message
        }
    }
}
