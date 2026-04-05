import Foundation

/// Errors from artifact resolution — mapping an ``Artifact`` spec
/// to a concrete download URL and format.
public enum ArtifactResolverError: Error, LocalizedError, Equatable, Sendable {

    /// No asset in the artifact matches the current platform.
    case noMatchingAsset(unitID: String, os: String, arch: String)

    /// The repository string is not in the expected `"owner/repo"` format.
    case invalidRepository(unitID: String, repo: String)

    /// The artifact type is not supported (only `github-release` for now).
    case unsupportedArtifactType(unitID: String, type: String)

    public var errorDescription: String? {
        switch self {
        case .noMatchingAsset(_, let os, let arch):
            "No matching artifact asset for \(os)/\(arch)"
        case .invalidRepository(_, let repo):
            "Invalid repository format: '\(repo)' (expected 'owner/repo')"
        case .unsupportedArtifactType(_, let type):
            "Unsupported artifact type: '\(type)'"
        }
    }
}
