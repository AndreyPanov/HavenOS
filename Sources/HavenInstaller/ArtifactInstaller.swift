import Foundation
import HavenCore

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
    private let fileManager: FileManager

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

        // 1. Check cache
        if cache.isCached(unitID: unitID) {
            return ArtifactInstallResult(
                unitID: unitID,
                installDirectory: cache.installDirectory(for: unitID),
                wasCached: true
            )
        }

        // 2. Resolve source to a local file
        let localFile: URL
        switch descriptor.source {
        case .local(let fileURL):
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw ArtifactInstallerError.sourceFileNotFound(
                    unitID: unitID,
                    path: fileURL.path
                )
            }
            localFile = fileURL

        case .remote(let remoteURL):
            do {
                localFile = try downloadClient.download(from: remoteURL)
            } catch {
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
        } catch {
            throw ArtifactInstallerError.installFailed(
                unitID: unitID,
                detail: error.localizedDescription
            )
        }

        // 4. Extract or copy
        switch descriptor.format {
        case .zip, .tarGz:
            do {
                try extractor.extract(
                    archiveURL: localFile,
                    to: installDir,
                    format: descriptor.format
                )
            } catch {
                // Clean up partial extraction
                try? cache.remove(unitID: unitID)
                throw ArtifactInstallerError.extractionFailed(
                    unitID: unitID,
                    detail: error.localizedDescription
                )
            }

        case .executable:
            do {
                let destFile = installDir.appendingPathComponent(
                    localFile.lastPathComponent
                )
                try fileManager.copyItem(at: localFile, to: destFile)
                // Make executable
                try fileManager.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: destFile.path
                )
            } catch {
                try? cache.remove(unitID: unitID)
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

        return ArtifactInstallResult(
            unitID: unitID,
            installDirectory: installDir,
            wasCached: false
        )
    }

    // MARK: - Uninstall

    /// Remove an installed artifact for the given unit.
    ///
    /// - Parameter unitID: The runtime unit identifier.
    public func uninstall(unitID: String) throws {
        try cache.remove(unitID: unitID)
    }
}
