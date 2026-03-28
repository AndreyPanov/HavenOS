import Foundation

/// Abstraction over archive extraction.
///
/// The protocol enables testing with mock extractors. The production
/// implementation (`ProcessArchiveExtractor`) uses system tools.
public protocol ArchiveExtractor: Sendable {

    /// Extract the archive at `archiveURL` into `destinationDirectory`.
    ///
    /// - Parameters:
    ///   - archiveURL: Path to the archive file.
    ///   - destinationDirectory: Directory to extract into (created if needed).
    ///   - format: The archive format.
    /// - Throws: If extraction fails.
    func extract(
        archiveURL: URL,
        to destinationDirectory: URL,
        format: ArtifactFormat
    ) throws
}
