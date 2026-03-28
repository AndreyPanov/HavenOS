import Foundation

/// Errors from artifact installation operations.
///
/// These errors use service-oriented language. Implementation details
/// like specific archive formats or shell commands are captured in the
/// `detail` field for diagnostics but should not be shown to end users.
public enum ArtifactInstallerError: Error, Equatable, Sendable {

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
}
