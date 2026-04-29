import Foundation
import HavenCore

/// Performs backup and restore operations for Haven capabilities.
///
/// Backs up media files only — no databases, no credentials, no service config.
/// Each capability backs up to its own user-chosen folder:
/// ```
/// /Volumes/NAS/Books/            (user-chosen for Books)
///   manifest.json
///   data/                        (user content — books, music, movies)
/// ```
public struct BackupEngine: Sendable {

    /// Injectable file manager for testing.
    private nonisolated(unsafe) let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Backup

    /// Back up a single capability's media files to its designated destination.
    public func backupCapability(
        scope: CapabilityBackupScope,
        destination: URL,
        displayName: String? = nil,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> CapabilityBackupEntry {
        let name = displayName ?? scope.capabilityID
        progress?("Backing up \(name)…")

        try ensureDestinationReachable(destination)

        let capabilityRoot = destination.appendingPathComponent(name)
        try ensureDestinationReachable(capabilityRoot)

        let dataRoot = capabilityRoot.appendingPathComponent("data")
        try ensureDestinationReachable(dataRoot)

        var entryStatus: CapabilityBackupEntry.EntryStatus = .complete

        if scope.contentPaths.isEmpty {
            entryStatus = .failed
        }

        // Step 1: Collect all items from all content folders into one flat list.
        // If two folders contain the same filename, the last folder wins.
        var allItems: [(name: String, source: URL)] = []
        var seenNames = Set<String>()

        for contentPath in scope.contentPaths {
            guard fileManager.fileExists(atPath: contentPath.path) else { continue }
            do {
                let items = try fileManager.contentsOfDirectory(
                    at: contentPath,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
                )
                for item in items {
                    let itemName = item.lastPathComponent
                    if seenNames.contains(itemName) {
                        allItems.removeAll { $0.name == itemName }
                    }
                    seenNames.insert(itemName)
                    allItems.append((name: itemName, source: item))
                }
            } catch {
                entryStatus = .partial
            }
        }

        // Step 2: Remove backup items that no longer exist in any source folder.
        if fileManager.fileExists(atPath: dataRoot.path) {
            let destItems = try fileManager.contentsOfDirectory(
                at: dataRoot, includingPropertiesForKeys: nil
            )
            for destItem in destItems where !seenNames.contains(destItem.lastPathComponent) {
                try? fileManager.removeItem(at: destItem)
            }
        }

        // Step 3: Copy new/changed items, skip unchanged ones.
        let totalItems = allItems.count
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        var totalBytes: UInt64 = 0
        var copiedCount = 0
        var skippedCount = 0

        for (index, entry) in allItems.enumerated() {
            let destItem = dataRoot.appendingPathComponent(entry.name)

            if fileManager.fileExists(atPath: destItem.path),
               filesMatch(entry.source, destItem, keys: resourceKeys) {
                skippedCount += 1
                totalBytes += fileOrDirectorySize(at: destItem)
                if totalItems > 5 {
                    progress?("\(name): \(index + 1) of \(totalItems) — \(entry.name) (unchanged)")
                }
                continue
            }

            copiedCount += 1
            progress?("\(name): Copying \(index + 1) of \(totalItems) — \(entry.name)")

            if fileManager.fileExists(atPath: destItem.path) {
                try fileManager.removeItem(at: destItem)
            }
            try fileManager.copyItem(at: entry.source, to: destItem)
            totalBytes += fileOrDirectorySize(at: destItem)
        }

        if copiedCount == 0 && skippedCount > 0 {
            progress?("\(name): All \(skippedCount) items up to date")
        }

        // Write manifest
        let capEntry = CapabilityBackupEntry(
            capabilityID: scope.capabilityID,
            displayName: name,
            bundleID: scope.bundleID,
            totalBytes: totalBytes,
            status: entryStatus
        )

        let manifest = BackupManifest(capabilities: [capEntry])
        let manifestData = try manifest.encode()
        let manifestFile = capabilityRoot.appendingPathComponent(BackupManifest.fileName)
        try manifestData.write(to: manifestFile, options: .atomic)

        progress?("Backup of \(name) complete.")
        return capEntry
    }

    /// Back up all configured capabilities.
    public func backupAll(
        scopes: [CapabilityBackupScope],
        destinations: [String: URL],
        displayNames: [String: String] = [:],
        progress: (@Sendable (String) -> Void)? = nil
    ) throws -> [CapabilityBackupEntry] {
        var entries: [CapabilityBackupEntry] = []

        for scope in scopes {
            guard let dest = destinations[scope.capabilityID] else { continue }

            let entry = try backupCapability(
                scope: scope,
                destination: dest,
                displayName: displayNames[scope.capabilityID],
                progress: progress
            )
            entries.append(entry)
        }

        progress?("Backup complete.")
        return entries
    }

    // MARK: - Restore

    /// Copy media files from a backup back to a library folder.
    ///
    /// This is the simple restore: takes the data/ contents from the backup
    /// and copies them into the user's chosen library path.
    public func restoreFiles(
        from backupDestination: URL,
        to libraryPath: URL,
        displayName: String? = nil,
        progress: (@Sendable (String) -> Void)? = nil
    ) throws {
        let capRoot = try findCapabilityRoot(in: backupDestination)
        let dataRoot = capRoot.appendingPathComponent("data")
        let label = displayName ?? "Restore"

        guard fileManager.fileExists(atPath: dataRoot.path) else {
            throw BackupError.manifestNotFound(path: backupDestination.path)
        }

        try ensureDestinationReachable(libraryPath)
        try copyDirectoryContentsWithProgress(
            from: dataRoot, to: libraryPath, label: label, progress: progress
        )

        progress?("Restore of \(label) complete.")
    }

    // MARK: - Read Manifest

    /// Read the manifest from a backup destination without restoring.
    public func readManifest(from destination: URL) throws -> BackupManifest {
        let capRoot = try findCapabilityRoot(in: destination)
        let manifestFile = capRoot.appendingPathComponent(BackupManifest.fileName)
        let data = try Data(contentsOf: manifestFile)
        return try BackupManifest.decode(from: data)
    }

    // MARK: - Private

    /// Find the capability root folder inside a backup destination.
    /// Checks both: the folder itself, and its subfolders.
    private func findCapabilityRoot(in destination: URL) throws -> URL {
        // Check if the folder itself is a capability root
        let directManifest = destination.appendingPathComponent(BackupManifest.fileName)
        if fileManager.fileExists(atPath: directManifest.path) {
            return destination
        }

        // Check subfolders
        guard let contents = try? fileManager.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            throw BackupError.manifestNotFound(path: destination.path)
        }

        for item in contents {
            let manifestFile = item.appendingPathComponent(BackupManifest.fileName)
            if fileManager.fileExists(atPath: manifestFile.path) {
                return item
            }
        }

        throw BackupError.manifestNotFound(path: destination.path)
    }

    /// Incrementally sync directory contents with progress reporting.
    @discardableResult
    private func copyDirectoryContentsWithProgress(
        from source: URL,
        to destination: URL,
        label: String?,
        progress: (@Sendable (String) -> Void)?
    ) throws -> UInt64 {
        guard fileManager.fileExists(atPath: source.path) else { return 0 }

        let sourceItems = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )

        let totalItems = sourceItems.count
        let prefix = label ?? "Backup"
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]

        // Remove destination items that no longer exist in source
        if fileManager.fileExists(atPath: destination.path) {
            let sourceNames = Set(sourceItems.map(\.lastPathComponent))
            let destItems = try fileManager.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            )
            for destItem in destItems where !sourceNames.contains(destItem.lastPathComponent) {
                try? fileManager.removeItem(at: destItem)
            }
        }

        var total: UInt64 = 0
        var copiedCount = 0
        var skippedCount = 0

        for (index, sourceItem) in sourceItems.enumerated() {
            let destItem = destination.appendingPathComponent(sourceItem.lastPathComponent)

            if fileManager.fileExists(atPath: destItem.path),
               filesMatch(sourceItem, destItem, keys: resourceKeys) {
                skippedCount += 1
                total += fileOrDirectorySize(at: destItem)
                if totalItems > 5 {
                    progress?("\(prefix): \(index + 1) of \(totalItems) — \(sourceItem.lastPathComponent) (unchanged)")
                }
                continue
            }

            copiedCount += 1
            progress?("\(prefix): Copying \(index + 1) of \(totalItems) — \(sourceItem.lastPathComponent)")

            if fileManager.fileExists(atPath: destItem.path) {
                try fileManager.removeItem(at: destItem)
            }
            try fileManager.copyItem(at: sourceItem, to: destItem)
            total += fileOrDirectorySize(at: destItem)
        }

        if copiedCount == 0 && skippedCount > 0 {
            progress?("\(prefix): All \(skippedCount) items up to date")
        }

        return total
    }

    private func filesMatch(_ a: URL, _ b: URL, keys: Set<URLResourceKey>) -> Bool {
        guard let aVals = try? a.resourceValues(forKeys: keys),
              let bVals = try? b.resourceValues(forKeys: keys) else {
            return false
        }
        if aVals.fileSize != bVals.fileSize { return false }
        if let aDate = aVals.contentModificationDate,
           let bDate = bVals.contentModificationDate {
            return abs(aDate.timeIntervalSince(bDate)) < 1.0
        }
        return false
    }

    private func fileOrDirectorySize(at url: URL) -> UInt64 {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if isDir.boolValue {
            return directorySize(at: url)
        }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { UInt64($0) } ?? 0
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
}
