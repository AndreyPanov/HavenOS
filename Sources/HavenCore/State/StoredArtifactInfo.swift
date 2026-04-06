import Foundation

/// Persisted metadata about an installed artifact for a runtime unit.
///
/// Records which repo, version, and asset were installed so that Haven
/// can support diagnostics, reinstall decisions, and future upgrade flows.
public struct StoredArtifactInfo: Codable, Equatable, Sendable {

    /// The runtime unit ID this artifact was installed for.
    public let unitID: String

    /// The source repository (e.g. `"owner/repo"`).
    public let repo: String

    /// The version tag that was installed (e.g. `"v1.0.0"`).
    public let version: String

    /// The asset filename that was downloaded (e.g. `"app-macos-arm64.zip"`).
    public let assetFile: String

    /// The platform string (e.g. `"macos/arm64"`).
    public let platform: String

    /// The archive format used (e.g. `"zip"`, `"tar.gz"`, `"executable"`).
    public let format: String

    public init(
        unitID: String,
        repo: String,
        version: String,
        assetFile: String,
        platform: String,
        format: String
    ) {
        self.unitID = unitID
        self.repo = repo
        self.version = version
        self.assetFile = assetFile
        self.platform = platform
        self.format = format
    }
}
