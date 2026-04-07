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

    /// The filesystem path where the artifact was installed.
    public let installDirectory: String

    /// The entrypoint command from the spec, if any (e.g. `"./my-server"`).
    public let entrypoint: String?

    public init(
        unitID: String,
        repo: String,
        version: String,
        assetFile: String,
        platform: String,
        format: String,
        installDirectory: String,
        entrypoint: String? = nil
    ) {
        self.unitID = unitID
        self.repo = repo
        self.version = version
        self.assetFile = assetFile
        self.platform = platform
        self.format = format
        self.installDirectory = installDirectory
        self.entrypoint = entrypoint
    }

    // MARK: - Backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case unitID, repo, version, assetFile, platform, format
        case installDirectory, entrypoint
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unitID = try c.decode(String.self, forKey: .unitID)
        repo = try c.decode(String.self, forKey: .repo)
        version = try c.decode(String.self, forKey: .version)
        assetFile = try c.decode(String.self, forKey: .assetFile)
        platform = try c.decode(String.self, forKey: .platform)
        format = try c.decode(String.self, forKey: .format)
        installDirectory = try c.decodeIfPresent(String.self, forKey: .installDirectory) ?? ""
        entrypoint = try c.decodeIfPresent(String.self, forKey: .entrypoint)
    }
}
