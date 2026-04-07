import Foundation

/// Errors from artifact installation operations.
///
/// These errors use service-oriented language. Implementation details
/// like specific archive formats or shell commands are captured in the
/// `detail` field for diagnostics but should not be shown to end users.
public enum ArtifactInstallerError: Error, LocalizedError, Equatable, Sendable {

    /// The local source file does not exist.
    case sourceFileNotFound(unitID: String, path: String)

    /// The download failed.
    case downloadFailed(unitID: String, url: String, detail: String)

    /// The artifact could not be extracted.
    case extractionFailed(unitID: String, detail: String)

    /// The archive format is not supported.
    case unsupportedFormat(unitID: String, detail: String)

    /// The expected artifact was not found after installation.
    case artifactNotFound(unitID: String, path: String)

    /// Failed to copy or write the artifact to the install directory.
    case installFailed(unitID: String, detail: String)

    /// No executable was found in the install directory after extraction.
    case executableNotFound(unitID: String, directory: String)

    /// The entrypoint path is invalid (absolute path, path traversal, or empty).
    case invalidEntrypointPath(unitID: String, path: String)

    public var errorDescription: String? {
        switch self {
        case .sourceFileNotFound(_, let path):
            "Source file not found: \(path)"
        case .downloadFailed(_, let url, let detail):
            "Download failed for \(url): \(detail)"
        case .extractionFailed(_, let detail):
            "Extraction failed: \(detail)"
        case .unsupportedFormat(_, let detail):
            "Unsupported format: \(detail)"
        case .artifactNotFound(_, let path):
            "Artifact not found: \(path)"
        case .installFailed(_, let detail):
            "Install failed: \(detail)"
        case .executableNotFound(_, let directory):
            "No executable found after extraction in: \(directory)"
        case .invalidEntrypointPath(_, let path):
            "Invalid entrypoint path '\(path)': must be a relative path without path traversal"
        }
    }
}
