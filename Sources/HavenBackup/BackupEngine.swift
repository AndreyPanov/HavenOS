import Foundation
import HavenCore

/// Performs backup and restore operations for Haven capabilities.
///
/// Backup layout at destination:
/// ```
/// <destination>/
///   manifest.json
///   state/
///     services.json
///   credentials/
///     credentials.json
///   capabilities/
///     <capabilityID>/
///       data/
///       config/
///       ...
/// ```
public struct BackupEngine: Sendable {

    /// Injectable file manager for testing.
    private nonisolated(unsafe) let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Backup

    /// Perform a full backup of the specified capabilities.
    ///
    /// - Parameters:
    ///   - scopes: Per-capability backup scopes (from `BackupScope`).
    ///   - destination: Root URL of the backup destination.
    ///   - stateFileURL: URL of the services.json state file.
    ///   - credentialKeys: UserDefaults keys to export as credentials.
    ///   - defaults: UserDefaults instance to read credentials from.
    ///   - displayNames: Map of capability ID → display name for the manifest.
    ///   - progress: Called with status updates during backup.
    /// - Returns: The backup manifest describing what was backed up.
    public func backup(
        scopes: [CapabilityBackupScope],
        destination: URL,
        stateFileURL: URL,
        credentialKeys: [String] = [],
        defaults: UserDefaults = .standard,
        displayNames: [String: String] = [:],
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> BackupManifest {
        // Validate destination
        try ensureDestinationReachable(destination)

        var entries: [CapabilityBackupEntry] = []

        // Back up each capability
        for scope in scopes {
            let name = displayNames[scope.capabilityID] ?? scope.capabilityID
            progress?("Backing up \(name)…")

            let capDir = destination
                .appendingPathComponent("capabilities")
                .appendingPathComponent(scope.capabilityID)

            var relativePaths: [String] = []
            var totalBytes: UInt64 = 0
            var entryStatus: CapabilityBackupEntry.EntryStatus = .complete

            // Copy state paths (data, config, etc.)
            for sourcePath in scope.statePaths {
                do {
                    let relPath = "capabilities/\(scope.capabilityID)/\(sourcePath.lastPathComponent)"
                    let destPath = capDir.appendingPathComponent(sourcePath.lastPathComponent)
                    let bytes = try copyDirectory(from: sourcePath, to: destPath)
                    relativePaths.append(relPath)
                    totalBytes += bytes
                } catch {
                    // Mark as partial if a state path fails but continue
                    entryStatus = .partial
                }
            }

            // Copy content paths (user media files)
            for sourcePath in scope.contentPaths {
                do {
                    let safeName = sourcePath.lastPathComponent
                    let relPath = "capabilities/\(scope.capabilityID)/content_\(safeName)"
                    let destPath = capDir.appendingPathComponent("content_\(safeName)")
                    let bytes = try copyDirectory(from: sourcePath, to: destPath)
                    relativePaths.append(relPath)
                    totalBytes += bytes
                } catch {
                    entryStatus = .partial
                }
            }

            if relativePaths.isEmpty {
                entryStatus = .failed
            }

            entries.append(CapabilityBackupEntry(
                capabilityID: scope.capabilityID,
                displayName: name,
                bundleID: scope.bundleID,
                relativePaths: relativePaths,
                totalBytes: totalBytes,
                status: entryStatus
            ))
        }

        // Back up services.json
        progress?("Backing up service state…")
        let stateDir = destination.appendingPathComponent("state")
        try fileManager.createDirectory(at: stateDir, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: stateFileURL.path) {
            let destStateFile = stateDir.appendingPathComponent("services.json")
            try? fileManager.removeItem(at: destStateFile)
            try fileManager.copyItem(at: stateFileURL, to: destStateFile)
        }

        // Export credentials
        progress?("Backing up credentials…")
        let includesCredentials = !credentialKeys.isEmpty
        if includesCredentials {
            let credsDir = destination.appendingPathComponent("credentials")
            try fileManager.createDirectory(at: credsDir, withIntermediateDirectories: true)
            let credsData = exportCredentials(keys: credentialKeys, from: defaults)
            let credsFile = credsDir.appendingPathComponent("credentials.json")
            try credsData.write(to: credsFile, options: .atomic)
        }

        // Write manifest
        let manifest = BackupManifest(
            capabilities: entries,
            includesCredentials: includesCredentials,
            includesState: fileManager.fileExists(atPath: stateFileURL.path)
        )
        let manifestData = try manifest.encode()
        let manifestFile = destination.appendingPathComponent(BackupManifest.fileName)
        try manifestData.write(to: manifestFile, options: .atomic)

        progress?("Backup complete.")
        return manifest
    }

    // MARK: - Restore

    /// Restore capabilities from a backup.
    ///
    /// - Parameters:
    ///   - source: Root URL of the backup to restore from.
    ///   - capabilityIDs: Which capabilities to restore. Nil means restore all.
    ///   - havenPaths: The Haven paths on the target machine.
    ///   - defaults: UserDefaults instance to import credentials into.
    ///   - progress: Called with status updates during restore.
    /// - Returns: The manifest that was restored.
    public func restore(
        from source: URL,
        capabilityIDs: Set<String>? = nil,
        havenPaths: HavenPaths,
        defaults: UserDefaults = .standard,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> BackupManifest {
        // Read manifest
        let manifestFile = source.appendingPathComponent(BackupManifest.fileName)
        guard fileManager.fileExists(atPath: manifestFile.path) else {
            throw BackupError.manifestNotFound(path: source.path)
        }

        let manifestData = try Data(contentsOf: manifestFile)
        let manifest = try BackupManifest.decode(from: manifestData)

        guard manifest.version <= BackupManifest.currentVersion else {
            throw BackupError.unsupportedManifestVersion(
                found: manifest.version,
                supported: BackupManifest.currentVersion
            )
        }

        // Filter capabilities to restore
        let toRestore = manifest.capabilities.filter { entry in
            guard entry.status != .failed else { return false }
            if let ids = capabilityIDs {
                return ids.contains(entry.capabilityID)
            }
            return true
        }

        // Restore each capability's directories
        for entry in toRestore {
            progress?("Restoring \(entry.displayName)…")

            let layout = havenPaths.serviceLayout(for: entry.capabilityID)

            for relPath in entry.relativePaths {
                let sourceDir = source.appendingPathComponent(relPath)
                guard fileManager.fileExists(atPath: sourceDir.path) else { continue }

                // Determine destination based on directory name
                let dirName = URL(fileURLWithPath: relPath).lastPathComponent
                let destDir: URL
                if dirName == "data" {
                    destDir = layout.data
                } else if dirName == "config" {
                    destDir = layout.config
                } else if dirName.hasPrefix("content_") {
                    // Content dirs are restored to their original role location
                    destDir = layout.serviceRoot.appendingPathComponent(dirName)
                } else {
                    destDir = layout.serviceRoot.appendingPathComponent(dirName)
                }

                try copyDirectory(from: sourceDir, to: destDir)
            }
        }

        // Restore services.json
        if manifest.includesState {
            progress?("Restoring service state…")
            let sourceState = source
                .appendingPathComponent("state")
                .appendingPathComponent("services.json")
            if fileManager.fileExists(atPath: sourceState.path) {
                let destState = havenPaths.stateFile
                try fileManager.createDirectory(
                    at: destState.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? fileManager.removeItem(at: destState)
                try fileManager.copyItem(at: sourceState, to: destState)
            }
        }

        // Restore credentials
        if manifest.includesCredentials {
            progress?("Restoring credentials…")
            let credsFile = source
                .appendingPathComponent("credentials")
                .appendingPathComponent("credentials.json")
            if fileManager.fileExists(atPath: credsFile.path) {
                try importCredentials(from: credsFile, into: defaults)
            }
        }

        progress?("Restore complete.")
        return manifest
    }

    // MARK: - Read Manifest

    /// Read the manifest from a backup location without restoring.
    public func readManifest(from source: URL) throws -> BackupManifest {
        let manifestFile = source.appendingPathComponent(BackupManifest.fileName)
        guard fileManager.fileExists(atPath: manifestFile.path) else {
            throw BackupError.manifestNotFound(path: source.path)
        }
        let data = try Data(contentsOf: manifestFile)
        return try BackupManifest.decode(from: data)
    }

    // MARK: - Credential Key Discovery

    /// Returns all UserDefaults keys that match Haven credential patterns.
    ///
    /// Scans for keys with known prefixes:
    /// - `haven.kavita.*`
    /// - `haven.navidrome.*`
    /// - `haven.jellyfin.*`
    public static func discoverCredentialKeys(
        from defaults: UserDefaults = .standard
    ) -> [String] {
        let prefixes = ["haven.kavita.", "haven.navidrome.", "haven.jellyfin."]
        return defaults.dictionaryRepresentation().keys.filter { key in
            prefixes.contains(where: { key.hasPrefix($0) })
        }.sorted()
    }

    // MARK: - Private

    private func ensureDestinationReachable(_ url: URL) throws {
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
            guard isDir.boolValue else {
                throw BackupError.destinationUnreachable(path: url.path)
            }
        } else {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw BackupError.destinationUnreachable(path: url.path)
            }
        }
    }

    /// Copy a directory tree, replacing the destination if it exists.
    /// Returns total bytes copied.
    @discardableResult
    private func copyDirectory(from source: URL, to destination: URL) throws -> UInt64 {
        guard fileManager.fileExists(atPath: source.path) else { return 0 }

        // Remove existing destination to ensure clean copy
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        // Ensure parent directory exists
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try fileManager.copyItem(at: source, to: destination)
        return directorySize(at: destination)
    }

    private func directorySize(at url: URL) -> UInt64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    private func exportCredentials(
        keys: [String],
        from defaults: UserDefaults
    ) -> Data {
        var dict: [String: String] = [:]
        for key in keys {
            if let value = defaults.string(forKey: key) {
                dict[key] = value
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(dict)) ?? Data("{}".utf8)
    }

    private func importCredentials(
        from file: URL,
        into defaults: UserDefaults
    ) throws {
        let data = try Data(contentsOf: file)
        let dict = try JSONDecoder().decode([String: String].self, from: data)
        for (key, value) in dict {
            defaults.set(value, forKey: key)
        }
    }
}
