import Foundation
import HavenCore

/// Performs backup and restore operations for Haven capabilities.
///
/// Each capability backs up to its own user-chosen folder with a clean two-folder layout:
/// ```
/// /Volumes/NAS/Books/            (user-chosen for Books)
///   config/                      (service internals + Haven metadata)
///     service_config/            (from service config dir)
///     service_data/              (from service data dir)
///     manifest.json
///     state.json
///     credentials.json
///   data/                        (user content — books, music, movies)
/// ```
public struct BackupEngine: Sendable {

    /// Injectable file manager for testing.
    private nonisolated(unsafe) let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Backup

    /// Back up a single capability to its designated destination.
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

        // Create a root folder named after the capability
        let capabilityRoot = destination.appendingPathComponent(name)
        try ensureDestinationReachable(capabilityRoot)

        let configRoot = capabilityRoot.appendingPathComponent("config")
        let dataRoot = capabilityRoot.appendingPathComponent("data")
        try ensureDestinationReachable(configRoot)
        try ensureDestinationReachable(dataRoot)

        var relativePaths: [String] = []
        var totalBytes: UInt64 = 0
        var entryStatus: CapabilityBackupEntry.EntryStatus = .complete

        // Copy service state paths (config, data, other persistent dirs) into config/
        for sourcePath in scope.statePaths {
            do {
                let dirName = sourcePath.lastPathComponent
                let safeName = "service_\(dirName)"
                let destPath = configRoot.appendingPathComponent(safeName)
                let bytes = try copyDirectory(from: sourcePath, to: destPath)
                relativePaths.append("config/\(safeName)")
                totalBytes += bytes
            } catch {
                entryStatus = .partial
            }
        }

        // Copy user content directly into data/ (no extra subfolder)
        for sourcePath in scope.contentPaths {
            do {
                let bytes = try copyDirectoryContents(from: sourcePath, to: dataRoot)
                relativePaths.append("data")
                totalBytes += bytes
            } catch {
                entryStatus = .partial
            }
        }

        if relativePaths.isEmpty {
            entryStatus = .failed
        }

        // Save this capability's state slice into config/
        if let state = serviceState {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(state) {
                let stateFile = configRoot.appendingPathComponent("state.json")
                try? data.write(to: stateFile, options: .atomic)
            }
        }

        // Export this capability's credentials into config/
        if !credentialKeys.isEmpty {
            let credsData = exportCredentials(keys: credentialKeys, from: defaults)
            let credsFile = configRoot.appendingPathComponent("credentials.json")
            try? credsData.write(to: credsFile, options: .atomic)
        }

        // Write per-capability manifest into config/
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
        let manifestFile = configRoot.appendingPathComponent(BackupManifest.fileName)
        try manifestData.write(to: manifestFile, options: .atomic)

        progress?("Backup of \(name) complete.")
        return entry
    }

    /// Back up all configured capabilities.
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

    /// Restore a single capability from its backup destination.
    ///
    /// The destination contains a capability root folder (e.g. "Books/")
    /// with `config/` and `data/` inside it.
    public func restoreCapability(
        from source: URL,
        havenPaths: HavenPaths,
        defaults: UserDefaults = .standard,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> BackupManifest {
        let capRoot = try findCapabilityRoot(in: source)
        let configRoot = capRoot.appendingPathComponent("config")
        let manifestFile = configRoot.appendingPathComponent(BackupManifest.fileName)
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
            let sourceDir = capRoot.appendingPathComponent(relPath)
            guard fileManager.fileExists(atPath: sourceDir.path) else { continue }

            if relPath.hasPrefix("config/service_") {
                // Restore service internal dirs: config/service_config → layout.config, etc.
                let serviceDirName = String(relPath.dropFirst("config/service_".count))
                let destDir: URL
                if serviceDirName == "data" {
                    destDir = layout.data
                } else if serviceDirName == "config" {
                    destDir = layout.config
                } else {
                    destDir = layout.serviceRoot.appendingPathComponent(serviceDirName)
                }
                try copyDirectory(from: sourceDir, to: destDir)
            } else if relPath.hasPrefix("data/") {
                // Restore user content — copy back to original location from state
                let dirName = String(relPath.dropFirst("data/".count))
                let destDir = layout.serviceRoot.appendingPathComponent(dirName)
                try copyDirectory(from: sourceDir, to: destDir)
            }
        }

        // Restore state slice from config/
        if manifest.includesState {
            let stateFile = configRoot.appendingPathComponent("state.json")
            if fileManager.fileExists(atPath: stateFile.path) {
                let data = try Data(contentsOf: stateFile)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let serviceState = try? decoder.decode(StoredServiceState.self, from: data) {
                    let stateStore = FileStateStore(paths: havenPaths)
                    try? stateStore.upsert(serviceState)
                }
            }
        }

        // Restore credentials from config/
        if manifest.includesCredentials {
            let credsFile = configRoot.appendingPathComponent("credentials.json")
            if fileManager.fileExists(atPath: credsFile.path) {
                try importCredentials(from: credsFile, into: defaults)
            }
        }

        progress?("Restore of \(entry.displayName) complete.")
        return manifest
    }

    // MARK: - Read Manifest

    /// Read the manifest from a backup destination without restoring.
    ///
    /// The destination contains a capability root folder (e.g. "Books/")
    /// with `config/manifest.json` inside it.
    public func readManifest(from destination: URL) throws -> BackupManifest {
        let capRoot = try findCapabilityRoot(in: destination)
        let manifestFile = capRoot
            .appendingPathComponent("config")
            .appendingPathComponent(BackupManifest.fileName)
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

    /// Find the capability root folder inside a backup destination.
    /// The capability root is the first subfolder containing `config/manifest.json`.
    private func findCapabilityRoot(in destination: URL) throws -> URL {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            throw BackupError.manifestNotFound(path: destination.path)
        }

        for item in contents {
            let manifest = item
                .appendingPathComponent("config")
                .appendingPathComponent(BackupManifest.fileName)
            if fileManager.fileExists(atPath: manifest.path) {
                return item
            }
        }

        throw BackupError.manifestNotFound(path: destination.path)
    }

    /// Copy the contents of a source directory into a destination directory (flat, no nesting).
    @discardableResult
    private func copyDirectoryContents(from source: URL, to destination: URL) throws -> UInt64 {
        guard fileManager.fileExists(atPath: source.path) else { return 0 }

        let items = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        )

        var total: UInt64 = 0
        for item in items {
            let destItem = destination.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: destItem.path) {
                try fileManager.removeItem(at: destItem)
            }
            try fileManager.copyItem(at: item, to: destItem)
            total += directorySize(at: destItem)
        }
        return total
    }

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
