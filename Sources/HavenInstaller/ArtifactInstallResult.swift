import Foundation

/// The result of a successful artifact installation.
///
/// Contains the final installed location so that runtime adapters and
/// the execution layer can find the artifact on disk.
public struct ArtifactInstallResult: Equatable, Sendable {

    /// The runtime unit ID this artifact was installed for.
    public let unitID: String

    /// The root directory where the artifact was installed.
    /// For archives, this is the extraction directory.
    /// For executables, this is the directory containing the file.
    public let installDirectory: URL

    /// Whether the result came from a cache hit (no extraction was needed).
    public let wasCached: Bool

    public init(
        unitID: String,
        installDirectory: URL,
        wasCached: Bool
    ) {
        self.unitID = unitID
        self.installDirectory = installDirectory
        self.wasCached = wasCached
    }
}
