import Foundation

/// Describes an artifact to be fetched and installed.
///
/// An `ArtifactDescriptor` contains everything the installer needs to
/// know to fetch, cache, and extract an artifact for a runtime unit.
public struct ArtifactDescriptor: Equatable, Sendable {

    /// The runtime unit ID this artifact belongs to.
    public let unitID: String

    /// Where to fetch the artifact from.
    public let source: ArtifactSource

    /// The packaging format of the artifact.
    public let format: ArtifactFormat

    /// If `true`, the top-level directory inside an archive is stripped
    /// after extraction, moving its contents up one level.
    public let stripFirstDirectory: Bool

    /// The executable name from the spec's `entrypoint.command` field.
    /// When set, post-extraction validation checks for this specific file.
    public let entrypointCommand: String?

    public init(
        unitID: String,
        source: ArtifactSource,
        format: ArtifactFormat,
        stripFirstDirectory: Bool = false,
        entrypointCommand: String? = nil
    ) {
        self.unitID = unitID
        self.source = source
        self.format = format
        self.stripFirstDirectory = stripFirstDirectory
        self.entrypointCommand = entrypointCommand
    }
}
