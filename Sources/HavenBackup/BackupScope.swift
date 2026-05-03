import Foundation
import HavenCore

/// Determines which directories to back up for each installed capability.
///
/// Separates user content from Haven-managed service data so backups include
/// both library files and the service's own config/state.
public struct BackupScope: Sendable {

    public init() {}

    /// Compute the directories to back up for a single capability.
    ///
    /// - Parameters:
    ///   - state: The persisted state for the installed service.
    ///   - bundle: The bundle spec (for storage policies). Nil if spec unavailable.
    /// - Returns: A `CapabilityBackupScope` with content, config, and state paths.
    public func scope(
        for state: StoredServiceState,
        bundle: HavenCore.Bundle? = nil
    ) -> CapabilityBackupScope {
        let layout = state.directoryLayout
        let storage = bundle?.storage ?? [:]

        var contentPaths: [URL] = []
        var configPaths: [URL] = [layout.config]
        var statePaths: [URL] = [layout.data]

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

        // Also check storage policies. User-visible roles are library content;
        // persistent internal roles are service-managed state or config. Runtime
        // scratch/log/cache roles are intentionally excluded from backups.
        for (role, policy) in storage {
            let roleDir = layout.serviceRoot.appendingPathComponent(role)
            if policy.userVisible {
                appendUnique(roleDir, to: &contentPaths)
            } else if policy.persistent, !shouldExcludeServiceRole(role) {
                if role.lowercased().contains("config") {
                    appendUnique(roleDir, to: &configPaths)
                } else {
                    appendUnique(roleDir, to: &statePaths)
                }
            }
        }

        configPaths.removeAll { contentPaths.contains($0) }
        statePaths.removeAll { contentPaths.contains($0) || configPaths.contains($0) }

        return CapabilityBackupScope(
            capabilityID: state.capability,
            bundleID: state.bundleID,
            contentPaths: contentPaths,
            configPaths: configPaths,
            statePaths: statePaths,
            serviceState: state
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

    private func appendUnique(_ url: URL, to urls: inout [URL]) {
        if !urls.contains(url) {
            urls.append(url)
        }
    }

    private func shouldExcludeServiceRole(_ role: String) -> Bool {
        switch role.lowercased() {
        case "cache", "caches", "log", "logs", "run", "tmp", "temp", "temporary":
            true
        default:
            false
        }
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

    /// Service configuration directories captured under the capability backup.
    public let configPaths: [URL]

    /// Persistent service-managed data, databases, and metadata directories.
    public let statePaths: [URL]

    /// Persisted Haven service state captured with the backup.
    public let serviceState: StoredServiceState?

    public init(
        capabilityID: String,
        bundleID: String,
        contentPaths: [URL],
        configPaths: [URL] = [],
        statePaths: [URL] = [],
        serviceState: StoredServiceState? = nil
    ) {
        self.capabilityID = capabilityID
        self.bundleID = bundleID
        self.contentPaths = contentPaths
        self.configPaths = configPaths
        self.statePaths = statePaths
        self.serviceState = serviceState
    }
}
