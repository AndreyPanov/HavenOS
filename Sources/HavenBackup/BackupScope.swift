import Foundation
import HavenCore

/// Determines which directories to back up for each installed capability.
///
/// Uses `StoredServiceState.directoryLayout` and `Bundle.storage` policies
/// to produce a list of source paths per capability.
///
/// Rules:
/// - Back up: data, config directories (persistent service state)
/// - Back up: content directories (user-visible files like books, music, movies)
/// - Skip: logs, run directories (ephemeral)
/// - Skip: binaries in Installed/ (re-downloadable)
public struct BackupScope: Sendable {

    public init() {}

    /// Compute the directories to back up for a single capability.
    ///
    /// - Parameters:
    ///   - state: The persisted state for the installed service.
    ///   - bundle: The bundle spec (for storage policies). Nil if spec unavailable.
    /// - Returns: A `CapabilityBackupScope` with categorized paths.
    public func scope(
        for state: StoredServiceState,
        bundle: HavenCore.Bundle? = nil
    ) -> CapabilityBackupScope {
        let layout = state.directoryLayout
        let storage = bundle?.storage ?? [:]

        var contentPaths: [URL] = []
        var statePaths: [URL] = []

        // Data directory: always back up (contains databases, metadata)
        statePaths.append(layout.data)

        // Config directory: always back up (contains configuration files, secrets)
        statePaths.append(layout.config)

        // Check resolved settings for user-visible content paths
        // (e.g. library_path, music_path, movies_path, root_path)
        let contentSettingKeys = ["library_path", "music_path", "movies_path", "root_path"]
        for key in contentSettingKeys {
            if let path = state.resolvedSettings[key] {
                let expanded = NSString(string: path).expandingTildeInPath
                let url = URL(fileURLWithPath: expanded)
                contentPaths.append(url)
            }
        }

        // Also check storage policies for userVisible directories
        // that may have been mapped to custom paths via resolvedSettings
        for (role, policy) in storage {
            if policy.userVisible {
                // The content path is likely already captured via resolvedSettings above.
                // Check if there's a directory at the standard role location.
                let roleDir = layout.serviceRoot.appendingPathComponent(role)
                if !contentPaths.contains(roleDir) && !statePaths.contains(roleDir) {
                    contentPaths.append(roleDir)
                }
            } else if policy.persistent && role != "data" && role != "config" {
                // Additional persistent directories beyond data/config
                let roleDir = layout.serviceRoot.appendingPathComponent(role)
                if !statePaths.contains(roleDir) {
                    statePaths.append(roleDir)
                }
            }
        }

        // Logs and run are always excluded (ephemeral)

        return CapabilityBackupScope(
            capabilityID: state.capability,
            bundleID: state.bundleID,
            contentPaths: contentPaths,
            statePaths: statePaths
        )
    }

    /// Compute backup scopes for all installed capabilities.
    ///
    /// - Parameters:
    ///   - services: All installed service states.
    ///   - bundles: Available bundle specs keyed by bundle ID.
    /// - Returns: Array of per-capability backup scopes.
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
    /// These may be large and outside the Haven directory tree.
    public let contentPaths: [URL]

    /// Service state directories (config, data, metadata databases).
    /// These are inside the Haven directory tree.
    public let statePaths: [URL]

    /// All paths combined.
    public var allPaths: [URL] {
        statePaths + contentPaths
    }

    public init(
        capabilityID: String,
        bundleID: String,
        contentPaths: [URL],
        statePaths: [URL]
    ) {
        self.capabilityID = capabilityID
        self.bundleID = bundleID
        self.contentPaths = contentPaths
        self.statePaths = statePaths
    }
}
