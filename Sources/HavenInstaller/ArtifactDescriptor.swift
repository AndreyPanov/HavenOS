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

    public init(
        unitID: String,
        source: ArtifactSource,
        format: ArtifactFormat
    ) {
        self.unitID = unitID
        self.source = source
        self.format = format
    }
}
