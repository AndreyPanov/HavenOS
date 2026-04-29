import Foundation
import HavenCore

/// Determines which directories to back up for each installed capability.
///
/// Media files only — no databases, no credentials, no service config.
/// Backs up user content directories (books, music, movies).
public struct BackupScope: Sendable {

    public init() {}

    /// Compute the directories to back up for a single capability.
    ///
    /// - Parameters:
    ///   - state: The persisted state for the installed service.
    ///   - bundle: The bundle spec (for storage policies). Nil if spec unavailable.
    /// - Returns: A `CapabilityBackupScope` with content paths.
    public func scope(
        for state: StoredServiceState,
        bundle: HavenCore.Bundle? = nil
    ) -> CapabilityBackupScope {
        let layout = state.directoryLayout
        let storage = bundle?.storage ?? [:]

        var contentPaths: [URL] = []

        // All facades save content paths to the unified "content_paths" key
        // (semicolon-separated, may contain tildes).
        // Fallback: legacy per-capability keys for services installed before unification.
        if let unified = state.resolvedSettings["content_paths"], !unified.isEmpty {
            for path in unified.split(separator: ";").map(String.init) where !path.isEmpty {
                let expanded = NSString(string: path).expandingTildeInPath
                let url = URL(fileURLWithPath: expanded)
                if !contentPaths.contains(url) {
                    contentPaths.append(url)
                }
            }
        } else {
            // Legacy fallback: check per-capability single-path and multi-path keys
            let legacySingleKeys = ["library_path", "music_path", "movies_path", "root_path"]
            for key in legacySingleKeys {
                if let path = state.resolvedSettings[key] {
                    let expanded = NSString(string: path).expandingTildeInPath
                    let url = URL(fileURLWithPath: expanded)
                    if !contentPaths.contains(url) {
                        contentPaths.append(url)
                    }
                }
            }
            let legacyMultiKeys = ["library_paths", "movies_paths"]
            for key in legacyMultiKeys {
                if let multiPaths = state.resolvedSettings[key] {
                    for path in multiPaths.split(separator: ";").map(String.init) where !path.isEmpty {
                        let expanded = NSString(string: path).expandingTildeInPath
                        let url = URL(fileURLWithPath: expanded)
                        if !contentPaths.contains(url) {
                            contentPaths.append(url)
                        }
                    }
                }
            }
        }

        // Also check storage policies for userVisible directories
        for (role, policy) in storage {
            if policy.userVisible {
                let roleDir = layout.serviceRoot.appendingPathComponent(role)
                if !contentPaths.contains(roleDir) {
                    contentPaths.append(roleDir)
                }
            }
        }

        return CapabilityBackupScope(
            capabilityID: state.capability,
            bundleID: state.bundleID,
            contentPaths: contentPaths
        )
    }

    /// Compute backup scopes for all installed capabilities.
    public func scopeAll(
        services: [String: StoredServiceState],
        bundles: [String: HavenCore.Bundle] = [:]
    ) -> [CapabilityBackupScope] {
        services.values.map { state in
            scope(for: state, bundle: bundles[state.bundleID])
        }
        .sorted { $0.capabilityID < $1.capabilityID }
    }
}

/// The resolved set of paths to back up for one capability.
public struct CapabilityBackupScope: Equatable, Sendable {

    /// The capability ID.
    public let capabilityID: String

    /// The bundle ID.
    public let bundleID: String

    /// User content directories (books, music, movies).
    public let contentPaths: [URL]

    public init(
        capabilityID: String,
        bundleID: String,
        contentPaths: [URL]
    ) {
        self.capabilityID = capabilityID
        self.bundleID = bundleID
        self.contentPaths = contentPaths
    }
}
