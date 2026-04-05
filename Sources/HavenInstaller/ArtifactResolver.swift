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
        // 1. Validate artifact type
        guard artifact.type == .githubRelease else {
            throw ArtifactResolverError.unsupportedArtifactType(
                unitID: unitID,
                type: artifact.type.rawValue
            )
        }

        // 2. Validate repo format
        let repoParts = artifact.repo.split(separator: "/")
        guard repoParts.count == 2,
              !repoParts[0].isEmpty,
              !repoParts[1].isEmpty else {
            throw ArtifactResolverError.invalidRepository(
                unitID: unitID,
                repo: artifact.repo
            )
        }

        // 3. Find matching asset for current platform
        guard let asset = artifact.assets.first(where: {
            $0.os == platform.os && $0.arch == platform.arch
        }) else {
            throw ArtifactResolverError.noMatchingAsset(
                unitID: unitID,
                os: platform.os,
                arch: platform.arch
            )
        }

        // 4. Construct GitHub Release download URL
        let urlString = "https://github.com/\(artifact.repo)/releases/download/\(artifact.version)/\(asset.file)"
        guard let url = URL(string: urlString) else {
            throw ArtifactResolverError.invalidRepository(
                unitID: unitID,
                repo: artifact.repo
            )
        }

        // 5. Determine archive format
        let format: ArtifactFormat
        if let archiveFormat = artifact.archive?.format {
            // Explicit format from spec
            switch archiveFormat.lowercased() {
            case "zip":
                format = .zip
            case "tar.gz", "tgz":
                format = .tarGz
            default:
                // Fall back to filename detection
                format = ArtifactFormat.detect(from: asset.file) ?? .executable
            }
        } else {
            // Detect from filename
            format = ArtifactFormat.detect(from: asset.file) ?? .executable
        }

        // 6. Strip first directory flag
        let strip = artifact.archive?.stripFirstDirectory ?? false

        return ArtifactDescriptor(
            unitID: unitID,
            source: .remote(url),
            format: format,
            stripFirstDirectory: strip
        )
    }
}
