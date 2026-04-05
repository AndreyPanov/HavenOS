import Foundation

/// Describes how to fetch a service binary from an external source.
///
/// Embedded in a ``RuntimeUnit`` spec as the `"artifact"` field.
/// During installation, Haven uses this to download the correct
/// platform-specific binary automatically.
///
/// Currently supports GitHub Releases (`github-release`).
public struct Artifact: Codable, Equatable, Sendable {

    /// The type of artifact source.
    public enum ArtifactType: String, Codable, Equatable, Sendable {
        /// A binary attached to a GitHub Release.
        case githubRelease = "github-release"
    }

    /// The artifact source type (e.g. `github-release`).
    public let type: ArtifactType

    /// The GitHub repository in `"owner/repo"` format.
    public let repo: String

    /// The release version tag (e.g. `"v1.0.0"`).
    public let version: String

    /// Platform-specific asset entries. Each entry maps an OS/arch
    /// combination to a filename in the release.
    public let assets: [ArtifactAsset]

    /// Optional archive configuration. If omitted, the format is
    /// detected from the asset filename.
    public let archive: ArtifactArchive?

    public init(
        type: ArtifactType,
        repo: String,
        version: String,
        assets: [ArtifactAsset],
        archive: ArtifactArchive? = nil
    ) {
        self.type = type
        self.repo = repo
        self.version = version
        self.assets = assets
        self.archive = archive
    }
}

/// A single platform-specific asset within an ``Artifact``.
public struct ArtifactAsset: Codable, Equatable, Sendable {

    /// The operating system (e.g. `"macos"`).
    public let os: String

    /// The CPU architecture (e.g. `"arm64"`, `"x86_64"`).
    public let arch: String

    /// The filename of the asset in the release (e.g. `"app-macos-arm64.zip"`).
    public let file: String

    public init(os: String, arch: String, file: String) {
        self.os = os
        self.arch = arch
        self.file = file
    }
}

/// Archive extraction options for an ``Artifact``.
public struct ArtifactArchive: Codable, Equatable, Sendable {

    /// The archive format (e.g. `"zip"`, `"tar.gz"`).
    /// Overrides filename-based detection when present.
    public let format: String

    /// If `true`, the top-level directory inside the archive is
    /// stripped during extraction. Useful when archives wrap
    /// contents in a single folder.
    public let stripFirstDirectory: Bool?

    public init(format: String, stripFirstDirectory: Bool? = nil) {
        self.format = format
        self.stripFirstDirectory = stripFirstDirectory
    }
}
