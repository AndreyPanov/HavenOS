import Foundation
import HavenCore

/// Performs backup and restore operations for Haven capabilities.
///
/// Each capability backs up to its own user-chosen folder:
/// ```
/// /Volumes/NAS/Books/            (user-chosen for Books)
///   manifest.json
///   data/
///   config/
///   state.json                   (this capability's slice of services.json)
///   credentials.json             (this capability's credential keys)
///
/// /Volumes/NAS/Music/            (user-chosen for Music)
///   manifest.json
///   data/
///   config/
///   ...
/// ```
public struct BackupEngine: Sendable {

    /// Injectable file manager for testing.
    private nonisolated(unsafe) let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Backup

    /// Back up a single capability to its designated destination.
    ///
    /// - Parameters:
    ///   - scope: The backup scope for this capability.
    ///   - destination: Root URL of the backup folder for this capability.
    ///   - serviceState: The stored service state for this capability.
    ///   - credentialKeys: UserDefaults keys belonging to this capability.
    ///   - defaults: UserDefaults instance to read credentials from.
    ///   - displayName: Human-readable name for the manifest.
    ///   - progress: Called with status updates.
    /// - Returns: The capability backup entry describing what was backed up.
    public func backupCapability(
        scope: CapabilityBackupScope,
        destination: URL,
        serviceState: StoredServiceState?,
        credentialKeys: [String] = [],
        defaults: UserDefaults = .standard,
        displayName: String? = nil,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> CapabilityBackupEntry {
        let name = displayName ?? scope.capabilityID
        progress?("Backing up \(name)…")

        try ensureDestinationReachable(destination)

        var relativePaths: [String] = []
        var totalBytes: UInt64 = 0
        var entryStatus: CapabilityBackupEntry.EntryStatus = .complete

        // Copy state paths (data, config, etc.)
        for sourcePath in scope.statePaths {
            do {
                let dirName = sourcePath.lastPathComponent
                let destPath = destination.appendingPathComponent(dirName)
                let bytes = try copyDirectory(from: sourcePath, to: destPath)
                relativePaths.append(dirName)
                totalBytes += bytes
            } catch {
                entryStatus = .partial
            }
        }

        // Copy content paths (user media files)
        for sourcePath in scope.contentPaths {
            do {
                let safeName = "content_\(sourcePath.lastPathComponent)"
                let destPath = destination.appendingPathComponent(safeName)
                let bytes = try copyDirectory(from: sourcePath, to: destPath)
                relativePaths.append(safeName)
                totalBytes += bytes
            } catch {
                entryStatus = .partial
            }
        }

        if relativePaths.isEmpty {
            entryStatus = .failed
        }

        // Save this capability's state slice
        if let state = serviceState {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(state) {
                let stateFile = destination.appendingPathComponent("state.json")
                try? data.write(to: stateFile, options: .atomic)
            }
        }

        // Export this capability's credentials
        if !credentialKeys.isEmpty {
            let credsData = exportCredentials(keys: credentialKeys, from: defaults)
            let credsFile = destination.appendingPathComponent("credentials.json")
            try? credsData.write(to: credsFile, options: .atomic)
        }

        // Write per-capability manifest
        let entry = CapabilityBackupEntry(
            capabilityID: scope.capabilityID,
            displayName: name,
            bundleID: scope.bundleID,
            relativePaths: relativePaths,
            totalBytes: totalBytes,
            status: entryStatus
        )

        let manifest = BackupManifest(
            capabilities: [entry],
            includesCredentials: !credentialKeys.isEmpty,
            includesState: serviceState != nil
        )
        let manifestData = try manifest.encode()
        let manifestFile = destination.appendingPathComponent(BackupManifest.fileName)
        try manifestData.write(to: manifestFile, options: .atomic)

        progress?("Backup of \(name) complete.")
        return entry
    }

    /// Back up all configured capabilities.
    ///
    /// - Parameters:
    ///   - scopes: Per-capability backup scopes.
    ///   - destinations: Map of capability ID → destination URL.
    ///   - serviceStates: Map of capability ID → stored state.
    ///   - credentialKeys: All Haven credential keys to export.
    ///   - defaults: UserDefaults instance.
    ///   - displayNames: Map of capability ID → display name.
    ///   - progress: Status callback.
    /// - Returns: Array of per-capability backup entries.
    public func backupAll(
        scopes: [CapabilityBackupScope],
        destinations: [String: URL],
        serviceStates: [String: StoredServiceState] = [:],
        credentialKeys: [String] = [],
        defaults: UserDefaults = .standard,
        displayNames: [String: String] = [:],
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> [CapabilityBackupEntry] {
        var entries: [CapabilityBackupEntry] = []

        for scope in scopes {
            guard let dest = destinations[scope.capabilityID] else { continue }

            let capKeys = credentialKeys.filter { key in
                // Match keys belonging to this capability
                key.contains(scope.capabilityID)
            }

            let entry = try backupCapability(
                scope: scope,
                destination: dest,
                serviceState: serviceStates[scope.capabilityID],
                credentialKeys: capKeys,
                defaults: defaults,
                displayName: displayNames[scope.capabilityID],
                progress: progress
            )
            entries.append(entry)
        }

        progress?("Backup complete.")
        return entries
    }

    // MARK: - Restore

    /// Restore a single capability from its backup folder.
    ///
    /// - Parameters:
    ///   - source: Root URL of this capability's backup folder.
    ///   - havenPaths: The Haven paths on the target machine.
    ///   - defaults: UserDefaults instance for credential import.
    ///   - progress: Status callback.
    /// - Returns: The manifest from the backup.
    public func restoreCapability(
        from source: URL,
        havenPaths: HavenPaths,
        defaults: UserDefaults = .standard,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> BackupManifest {
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

        guard let entry = manifest.capabilities.first, entry.status != .failed else {
            return manifest
        }

        progress?("Restoring \(entry.displayName)…")

        let layout = havenPaths.serviceLayout(for: entry.capabilityID)

        for relPath in entry.relativePaths {
            let sourceDir = source.appendingPathComponent(relPath)
            guard fileManager.fileExists(atPath: sourceDir.path) else { continue }

            let dirName = URL(fileURLWithPath: relPath).lastPathComponent
            let destDir: URL
            if dirName == "data" {
                destDir = layout.data
            } else if dirName == "config" {
                destDir = layout.config
            } else {
                destDir = layout.serviceRoot.appendingPathComponent(dirName)
            }

            try copyDirectory(from: sourceDir, to: destDir)
        }

        // Restore state slice
        if manifest.includesState {
            let stateFile = source.appendingPathComponent("state.json")
            if fileManager.fileExists(atPath: stateFile.path) {
                let data = try Data(contentsOf: stateFile)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let serviceState = try? decoder.decode(StoredServiceState.self, from: data) {
                    // Merge into existing haven state
                    let stateStore = FileStateStore(paths: havenPaths)
                    try? stateStore.upsert(serviceState)
                }
            }
        }

        // Restore credentials
        if manifest.includesCredentials {
            let credsFile = source.appendingPathComponent("credentials.json")
            if fileManager.fileExists(atPath: credsFile.path) {
                try importCredentials(from: credsFile, into: defaults)
            }
        }

        progress?("Restore of \(entry.displayName) complete.")
        return manifest
    }

    // MARK: - Read Manifest

    /// Read the manifest from a capability backup location without restoring.
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

    @discardableResult
    private func copyDirectory(from source: URL, to destination: URL) throws -> UInt64 {
        guard fileManager.fileExists(atPath: source.path) else { return 0 }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

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
