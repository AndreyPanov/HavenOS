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
    /// 1. Check cache — if already installed, return immediately.
    /// 2. Resolve the source to a local file (copy or download).
    /// 3. Extract or place the artifact into the install directory.
    /// 4. Return metadata about the installation.
    ///
    /// - Parameter descriptor: What to install and where to get it.
    /// - Returns: The installation result with the final directory.
    /// - Throws: `ArtifactInstallerError` if any step fails.
    public func install(descriptor: ArtifactDescriptor) throws -> ArtifactInstallResult {
        let unitID = descriptor.unitID
        log.info("[install] unit=\(unitID), source=\(String(describing: descriptor.source)), format=\(String(describing: descriptor.format))")

        // 1. Check cache
        if cache.isCached(unitID: unitID) {
            let dir = cache.installDirectory(for: unitID)
            log.info("[install] Cache hit for \(unitID): \(dir.path)")
            return ArtifactInstallResult(
                unitID: unitID,
                installDirectory: dir,
                wasCached: true
            )
        }
        log.info("[install] Cache miss for \(unitID), resolving source...")

        // 2. Resolve source to a local file
        let localFile: URL
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
            localFile = fileURL

        case .remote(let remoteURL):
            log.info("[install] Downloading from: \(remoteURL.absoluteString)")
            do {
                localFile = try downloadClient.download(from: remoteURL)
                log.info("[install] Downloaded to: \(localFile.path)")
            } catch {
                log.error("[install] Download failed: \(error.localizedDescription)")
                throw ArtifactInstallerError.downloadFailed(
                    unitID: unitID,
                    url: remoteURL.absoluteString,
                    detail: error.localizedDescription
                )
            }
        }

        // 3. Prepare clean install directory
        let installDir: URL
        do {
            installDir = try cache.prepareCleanDirectory(for: unitID)
            log.info("[install] Prepared install dir: \(installDir.path)")
        } catch {
            throw ArtifactInstallerError.installFailed(
                unitID: unitID,
                detail: error.localizedDescription
            )
        }

        // 4. Extract or copy
        switch descriptor.format {
        case .zip, .tarGz:
            log.info("[install] Extracting archive to \(installDir.path)...")
            do {
                try extractor.extract(
                    archiveURL: localFile,
                    to: installDir,
                    format: descriptor.format
                )
                log.info("[install] Extraction complete")
            } catch {
                // Clean up partial extraction
                try? cache.remove(unitID: unitID)
                log.error("[install] Extraction failed: \(error.localizedDescription)")
                throw ArtifactInstallerError.extractionFailed(
                    unitID: unitID,
                    detail: error.localizedDescription
                )
            }

            // Strip the top-level directory if requested.
            if descriptor.stripFirstDirectory {
                do {
                    try stripFirstDirectory(in: installDir)
                    log.info("[install] Stripped first directory level")
                } catch {
                    try? cache.remove(unitID: unitID)
                    log.error("[install] Strip first directory failed: \(error.localizedDescription)")
                    throw ArtifactInstallerError.installFailed(
                        unitID: unitID,
                        detail: "Failed to strip first directory: \(error.localizedDescription)"
                    )
                }
            }

        case .executable:
            do {
                let destFile = installDir.appendingPathComponent(
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
                try? cache.remove(unitID: unitID)
                log.error("[install] Copy failed: \(error.localizedDescription)")
                throw ArtifactInstallerError.installFailed(
                    unitID: unitID,
                    detail: error.localizedDescription
                )
            }
        }

        // 5. Clean up downloaded file for remote sources
        if case .remote = descriptor.source {
            try? fileManager.removeItem(at: localFile)
        }

        log.info("[install] Artifact install complete for \(unitID)")
        return ArtifactInstallResult(
            unitID: unitID,
            installDirectory: installDir,
            wasCached: false
        )
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

        // Move all contents of the single directory up one level
        let innerContents = try fileManager.contentsOfDirectory(
            at: singleDir,
            includingPropertiesForKeys: nil
        )

        for item in innerContents {
            let destination = directory.appendingPathComponent(item.lastPathComponent)
            try fileManager.moveItem(at: item, to: destination)
        }

        // Remove the now-empty directory
        try fileManager.removeItem(at: singleDir)
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
