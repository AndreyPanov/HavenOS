import Foundation
import HavenCore
import os

private let log = Logger(subsystem: "com.haven", category: "ArtifactInstaller")

/// Fetches, caches, and places service artifacts in Haven-managed directories.
///
/// `ArtifactInstaller` is the primary API for installing artifacts. It handles:
/// 1. Resolving the source (local file or remote URL)
/// 2. Downloading remote artifacts (via `DownloadClient`)
/// 3. Checking the cache to avoid duplicate work
/// 4. Extracting archives (via `ArchiveExtractor`)
/// 5. Copying single executables
///
/// ## Architecture
///
/// ```
/// ArtifactDescriptor → ArtifactInstaller → <base>/Installed/<unit-id>/
/// ```
///
/// The installer uses three dependencies:
/// - `ArtifactCache` for cache management
/// - `DownloadClient` for fetching remote artifacts
/// - `ArchiveExtractor` for extracting archives
///
/// All three are injectable for testing.
public struct ArtifactInstaller: Sendable {

    private let cache: ArtifactCache
    private let downloadClient: any DownloadClient
    private let extractor: any ArchiveExtractor
    private let downloadsDirectory: URL
    private nonisolated(unsafe) let fileManager: FileManager

    /// Creates an installer with the given dependencies.
    ///
    /// - Parameters:
    ///   - cache: The artifact cache.
    ///   - downloadClient: Client for downloading remote artifacts.
    ///   - extractor: Extractor for archive formats.
    ///   - downloadsDirectory: Staging area for downloads.
    ///     Typically `HavenPaths.downloadsDirectory`.
    public init(
        cache: ArtifactCache,
        downloadClient: any DownloadClient = URLSessionDownloadClient(),
        extractor: any ArchiveExtractor = ProcessArchiveExtractor(),
        downloadsDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.cache = cache
        self.downloadClient = downloadClient
        self.extractor = extractor
        self.downloadsDirectory = downloadsDirectory
        self.fileManager = fileManager
    }

    /// Convenience initializer from `HavenPaths`.
    public init(
        paths: HavenPaths,
        downloadClient: any DownloadClient = URLSessionDownloadClient(),
        extractor: any ArchiveExtractor = ProcessArchiveExtractor()
    ) {
        self.init(
            cache: ArtifactCache(installedRoot: paths.installedDirectory),
            downloadClient: downloadClient,
            extractor: extractor,
            downloadsDirectory: paths.downloadsDirectory
        )
    }

    // MARK: - Install

    /// Install an artifact described by the given descriptor.
    ///
    /// For artifact-based installs (remote sources), uses atomic staging:
    /// files are extracted into a `.installing` temp directory, validated,
    /// then atomically renamed to the final location.
    ///
    /// - Parameters:
    ///   - descriptor: What to install and where to get it.
    ///   - forceReinstall: When `true`, bypasses the cache check and
    ///     re-downloads/re-extracts even if already installed.
    /// - Returns: The installation result with the final directory.
    /// - Throws: `ArtifactInstallerError` if any step fails.
    public func install(
        descriptor: ArtifactDescriptor,
        forceReinstall: Bool = false,
        downloadProgress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ArtifactInstallResult {
        let unitID = descriptor.unitID
        log.info("[install] unit=\(unitID), source=\(String(describing: descriptor.source)), format=\(String(describing: descriptor.format))")

        // 1. Check cache (unless force reinstall)
        if !forceReinstall && cache.isCached(unitID: unitID) {
            let dir = cache.installDirectory(for: unitID)
            // Validate that the cached directory actually contains a usable
            // executable. If not, treat as a broken cache and reinstall.
            if isCacheValid(descriptor: descriptor, directory: dir) {
                log.info("[install] Cache hit for \(unitID): \(dir.path)")
                return ArtifactInstallResult(
                    unitID: unitID,
                    installDirectory: dir,
                    wasCached: true
                )
            }
            log.warning("[install] Broken cache for \(unitID), reinstalling...")
            try? cache.remove(unitID: unitID)
        }
        log.info("[install] \(forceReinstall ? "Force reinstall" : "Cache miss") for \(unitID), resolving source...")

        // 2. Resolve source to a local file
        let localFile = try resolveLocalFile(descriptor: descriptor, downloadProgress: downloadProgress)

        // 3. Extract or copy into a work directory.
        //    Artifact-based installs use atomic staging; legacy uses direct directory.
        let useAtomicStaging = descriptor.entrypointCommand != nil
            || descriptor.stripFirstDirectory
            || forceReinstall
            || {
                if case .remote = descriptor.source { return true }
                return false
            }()

        let workDir: URL
        do {
            if useAtomicStaging {
                workDir = try cache.prepareStagingDirectory(for: unitID)
                log.info("[install] Prepared staging dir: \(workDir.path)")
            } else {
                workDir = try cache.prepareCleanDirectory(for: unitID)
                log.info("[install] Prepared install dir: \(workDir.path)")
            }
        } catch {
            throw ArtifactInstallerError.installFailed(
                unitID: unitID,
                detail: error.localizedDescription
            )
        }

        do {
            try extractOrCopy(descriptor: descriptor, localFile: localFile, to: workDir)

            // Post-extraction validation for artifact-based installs
            if useAtomicStaging {
                try validateExtraction(descriptor: descriptor, directory: workDir)
            }

            // Promote staging → final
            if useAtomicStaging {
                try cache.promoteStagingDirectory(for: unitID)
                log.info("[install] Promoted staging to final for \(unitID)")
            }
        } catch {
            // Clean up staging on failure (final dir is untouched)
            if useAtomicStaging {
                cache.removeStagingDirectory(for: unitID)
            } else {
                try? cache.remove(unitID: unitID)
            }
            throw error
        }

        // 4. Clean up downloaded file for remote sources
        if case .remote = descriptor.source {
            try? fileManager.removeItem(at: localFile)
        }

        let finalDir = cache.installDirectory(for: unitID)
        log.info("[install] Artifact install complete for \(unitID)")
        return ArtifactInstallResult(
            unitID: unitID,
            installDirectory: finalDir,
            wasCached: false
        )
    }

    // MARK: - Source resolution

    private func resolveLocalFile(descriptor: ArtifactDescriptor, downloadProgress: (@Sendable (Double) -> Void)? = nil) throws -> URL {
        let unitID = descriptor.unitID
        switch descriptor.source {
        case .local(let fileURL):
            log.info("[install] Local source: \(fileURL.path)")
            guard fileManager.fileExists(atPath: fileURL.path) else {
                log.error("[install] Source file not found: \(fileURL.path)")
                throw ArtifactInstallerError.sourceFileNotFound(
                    unitID: unitID,
                    path: fileURL.path
                )
            }
            return fileURL

        case .remote(let remoteURL):
            log.info("[install] Downloading from: \(remoteURL.absoluteString)")
            do {
                let localFile = try downloadClient.download(from: remoteURL, progress: downloadProgress)
                log.info("[install] Downloaded to: \(localFile.path)")
                return localFile
            } catch {
                log.error("[install] Download failed: \(error.localizedDescription)")
                throw ArtifactInstallerError.downloadFailed(
                    unitID: unitID,
                    url: remoteURL.absoluteString,
                    detail: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Extraction

    private func extractOrCopy(
        descriptor: ArtifactDescriptor,
        localFile: URL,
        to directory: URL
    ) throws {
        let unitID = descriptor.unitID
        switch descriptor.format {
        case .zip, .tarGz, .tarXz:
            log.info("[install] Extracting archive to \(directory.path)...")
            do {
                try extractor.extract(
                    archiveURL: localFile,
                    to: directory,
                    format: descriptor.format
                )
                log.info("[install] Extraction complete")
            } catch {
                log.error("[install] Extraction failed: \(error.localizedDescription)")
                throw ArtifactInstallerError.extractionFailed(
                    unitID: unitID,
                    detail: error.localizedDescription
                )
            }

            // Strip the top-level directory if requested.
            if descriptor.stripFirstDirectory {
                do {
                    try stripFirstDirectory(in: directory)
                    log.info("[install] Stripped first directory level")
                } catch {
                    log.error("[install] Strip first directory failed: \(error.localizedDescription)")
                    throw ArtifactInstallerError.installFailed(
                        unitID: unitID,
                        detail: "Failed to strip first directory: \(error.localizedDescription)"
                    )
                }
            }

        case .executable:
            do {
                let destFile = directory.appendingPathComponent(
                    localFile.lastPathComponent
                )
                log.info("[install] Copying executable: \(localFile.path) -> \(destFile.path)")
                try fileManager.copyItem(at: localFile, to: destFile)
                // Make executable
                try fileManager.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: destFile.path
                )
                log.info("[install] Executable copied and permissions set")
            } catch {
                log.error("[install] Copy failed: \(error.localizedDescription)")
                throw ArtifactInstallerError.installFailed(
                    unitID: unitID,
                    detail: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Post-extraction validation

    /// Validate that the extraction produced a usable result.
    ///
    /// - If `entrypointCommand` is set, validates the path (rejects absolute
    ///   paths), normalizes it (strips `./` prefix), then checks the file
    ///   exists and is executable in the install directory.
    /// - Otherwise, checks that at least one executable file exists (shallow).
    private func validateExtraction(
        descriptor: ArtifactDescriptor,
        directory: URL
    ) throws {
        let unitID = descriptor.unitID

        if let command = descriptor.entrypointCommand {
            // Reject absolute paths — artifact entrypoints must be relative
            guard !command.hasPrefix("/") else {
                log.error("[install] Absolute entrypoint path rejected: \(command)")
                throw ArtifactInstallerError.invalidEntrypointPath(
                    unitID: unitID,
                    path: command
                )
            }

            // Normalize: strip leading "./" if present
            let normalized = command.strippingDotSlashPrefix

            guard !normalized.isEmpty else {
                log.error("[install] Empty entrypoint command after normalization")
                throw ArtifactInstallerError.invalidEntrypointPath(
                    unitID: unitID,
                    path: command
                )
            }

            // Reject path traversal
            guard !normalized.contains("..") else {
                log.error("[install] Path traversal in entrypoint rejected: \(command)")
                throw ArtifactInstallerError.invalidEntrypointPath(
                    unitID: unitID,
                    path: command
                )
            }

            // Check for the specific named executable
            let expectedPath = directory.appendingPathComponent(normalized)
            guard fileManager.fileExists(atPath: expectedPath.path) else {
                log.error("[install] Expected executable '\(normalized)' not found in \(directory.path)")
                throw ArtifactInstallerError.executableNotFound(
                    unitID: unitID,
                    directory: directory.path
                )
            }
            guard fileManager.isExecutableFile(atPath: expectedPath.path) else {
                log.error("[install] Entrypoint '\(normalized)' exists but is not executable")
                throw ArtifactInstallerError.executableNotFound(
                    unitID: unitID,
                    directory: directory.path
                )
            }
            log.info("[install] Validated entrypoint command: \(normalized)")
        } else {
            // Check that at least one executable exists
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                throw ArtifactInstallerError.executableNotFound(
                    unitID: unitID,
                    directory: directory.path
                )
            }

            let hasExecutable = contents.contains { url in
                var isDir: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
                    && !isDir.boolValue
                    && fileManager.isExecutableFile(atPath: url.path)
            }

            guard hasExecutable else {
                log.error("[install] No executable found in \(directory.path)")
                throw ArtifactInstallerError.executableNotFound(
                    unitID: unitID,
                    directory: directory.path
                )
            }
            log.info("[install] Validated: executable found in extraction directory")
        }
    }

    // MARK: - Cache validation

    /// Check whether a cached directory contains a valid installation.
    ///
    /// - If `entrypointCommand` is set, checks for the specific file.
    /// - Otherwise, checks for at least one executable file (shallow).
    private func isCacheValid(descriptor: ArtifactDescriptor, directory: URL) -> Bool {
        if let command = descriptor.entrypointCommand {
            let normalized = command.strippingDotSlashPrefix
            guard !normalized.isEmpty else { return false }
            let path = directory.appendingPathComponent(normalized)
            return fileManager.isExecutableFile(atPath: path.path)
        }

        // No specific command — check for any executable
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        return contents.contains { url in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
                && !isDir.boolValue
                && fileManager.isExecutableFile(atPath: url.path)
        }
    }

    // MARK: - Strip first directory

    /// If the directory contains exactly one subdirectory (and no other items),
    /// move all of that subdirectory's contents up one level and remove the
    /// now-empty subdirectory.
    private func stripFirstDirectory(in directory: URL) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        // Filter to only directories
        let directories = contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        // Only strip if there is exactly one top-level directory and nothing else
        guard directories.count == 1, contents.count == 1,
              let singleDir = directories.first else {
            return
        }

        // Rename the directory to a temp name first to avoid conflicts
        // when inner items share the same name (e.g. Kavita/Kavita).
        let tempDir = directory.appendingPathComponent(".__haven_strip_temp__")
        try fileManager.moveItem(at: singleDir, to: tempDir)

        // Move all contents up one level
        let innerContents = try fileManager.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        )

        for item in innerContents {
            let destination = directory.appendingPathComponent(item.lastPathComponent)
            try fileManager.moveItem(at: item, to: destination)
        }

        // Remove the now-empty temp directory
        try fileManager.removeItem(at: tempDir)
    }

    // MARK: - Uninstall

    /// Remove an installed artifact for the given unit.
    ///
    /// - Parameter unitID: The runtime unit identifier.
    public func uninstall(unitID: String) throws {
        log.info("[uninstall] Removing artifact for unit: \(unitID)")
        try cache.remove(unitID: unitID)
        log.info("[uninstall] Artifact removed: \(unitID)")
    }
}
