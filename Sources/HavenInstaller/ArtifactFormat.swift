import Foundation

/// The packaging format of an artifact.
///
/// Haven needs to know the format to determine how to extract or place
/// the artifact after downloading/copying it.
public enum ArtifactFormat: Equatable, Sendable {

    /// A single executable file (no extraction needed).
    case executable

    /// A ZIP archive.
    case zip

    /// A gzip-compressed tar archive.
    case tarGz

    /// An xz-compressed tar archive.
    case tarXz

    /// Detect format from a filename or URL path.
    ///
    /// - Returns: The detected format, or `nil` if the extension is
    ///   not recognized.
    public static func detect(from path: String) -> ArtifactFormat? {
        let lowered = path.lowercased()
        if lowered.hasSuffix(".tar.gz") || lowered.hasSuffix(".tgz") {
            return .tarGz
        } else if lowered.hasSuffix(".tar.xz") || lowered.hasSuffix(".txz") {
            return .tarXz
        } else if lowered.hasSuffix(".zip") {
            return .zip
        }
        return nil
    }
}
