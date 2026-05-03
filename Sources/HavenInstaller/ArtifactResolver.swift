import Foundation
import HavenCore

/// Resolves an ``Artifact`` spec into an ``ArtifactDescriptor`` ready
/// for the installer.
///
/// Given a RuntimeUnit's artifact block, the resolver:
/// 1. Detects the current platform (OS + architecture)
/// 2. Finds the matching asset entry
/// 3. Constructs the download URL (GitHub Releases)
/// 4. Determines the archive format
/// 5. Returns an ``ArtifactDescriptor`` with the remote source
public enum ArtifactResolver {

    /// Resolve an artifact to a concrete download descriptor.
    ///
    /// - Parameters:
    ///   - artifact: The artifact spec from the RuntimeUnit.
    ///   - unitID: The runtime unit ID (for error messages).
    ///   - platform: The target platform. Defaults to the current machine.
    /// - Returns: An ``ArtifactDescriptor`` with a remote download URL.
    /// - Throws: ``ArtifactResolverError`` if resolution fails.
    public static func resolve(
        artifact: Artifact,
        unitID: String,
        platform: PlatformInfo = .current
    ) throws -> ArtifactDescriptor {
        switch artifact.type {
        case .githubRelease:
            return try resolveGitHubRelease(artifact: artifact, unitID: unitID, platform: platform)
        case .directURL:
            return try resolveDirectURL(artifact: artifact, unitID: unitID, platform: platform)
        }
    }

    // MARK: - GitHub Release

    private static func resolveGitHubRelease(
        artifact: Artifact,
        unitID: String,
        platform: PlatformInfo
    ) throws -> ArtifactDescriptor {
        // Validate repo format
        let repoParts = artifact.repo.split(separator: "/")
        guard repoParts.count == 2,
              !repoParts[0].isEmpty,
              !repoParts[1].isEmpty else {
            throw ArtifactResolverError.invalidRepository(
                unitID: unitID,
                repo: artifact.repo
            )
        }

        let asset = try matchAsset(artifact: artifact, unitID: unitID, platform: platform)

        // Construct GitHub Release download URL
        let urlString = "https://github.com/\(artifact.repo)/releases/download/\(artifact.version)/\(asset.file)"
        guard let url = URL(string: urlString) else {
            throw ArtifactResolverError.invalidRepository(
                unitID: unitID,
                repo: artifact.repo
            )
        }

        let format = resolveFormat(artifact: artifact, filename: asset.file)
        let strip = artifact.archive?.stripFirstDirectory ?? false

        return ArtifactDescriptor(
            unitID: unitID,
            source: .remote(url),
            format: format,
            stripFirstDirectory: strip
        )
    }

    // MARK: - Direct URL

    private static func resolveDirectURL(
        artifact: Artifact,
        unitID: String,
        platform: PlatformInfo
    ) throws -> ArtifactDescriptor {
        let asset = try matchAsset(artifact: artifact, unitID: unitID, platform: platform)

        guard let urlString = asset.url, let url = URL(string: urlString) else {
            throw ArtifactResolverError.missingAssetURL(unitID: unitID)
        }

        // Use asset.file for format detection if present, otherwise use the URL path
        let filename = asset.file.isEmpty ? url.lastPathComponent : asset.file
        let format = resolveFormat(artifact: artifact, filename: filename)
        let strip = artifact.archive?.stripFirstDirectory ?? false

        return ArtifactDescriptor(
            unitID: unitID,
            source: .remote(url),
            format: format,
            stripFirstDirectory: strip
        )
    }

    // MARK: - Helpers

    private static func matchAsset(
        artifact: Artifact,
        unitID: String,
        platform: PlatformInfo
    ) throws -> ArtifactAsset {
        guard let asset = artifact.assets.first(where: {
            platformMatches(assetOS: $0.os, assetArch: $0.arch, platform: platform)
        }) else {
            throw ArtifactResolverError.noMatchingAsset(
                unitID: unitID,
                os: platform.os,
                arch: platform.arch
            )
        }
        return asset
    }

    private static func platformMatches(
        assetOS: String,
        assetArch: String,
        platform: PlatformInfo
    ) -> Bool {
        normalizeOS(assetOS) == normalizeOS(platform.os)
            && normalizeArch(assetArch) == normalizeArch(platform.arch)
    }

    private static func normalizeOS(_ value: String) -> String {
        switch value.lowercased() {
        case "darwin", "macos", "osx":
            "macos"
        default:
            value.lowercased()
        }
    }

    private static func normalizeArch(_ value: String) -> String {
        switch value.lowercased() {
        case "amd64", "x64", "x86-64":
            "x86_64"
        default:
            value.lowercased()
        }
    }

    private static func resolveFormat(artifact: Artifact, filename: String) -> ArtifactFormat {
        if let archiveFormat = artifact.archive?.format {
            switch archiveFormat.lowercased() {
            case "zip":
                return .zip
            case "tar.gz", "tgz":
                return .tarGz
            case "tar.xz", "txz":
                return .tarXz
            default:
                return ArtifactFormat.detect(from: filename) ?? .executable
            }
        }
        return ArtifactFormat.detect(from: filename) ?? .executable
    }
}
