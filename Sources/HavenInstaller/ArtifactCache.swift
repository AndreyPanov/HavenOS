import Foundation
import HavenCore

/// Manages the installed artifact cache under `<base>/Installed/`.
///
/// Each runtime unit gets its own subdirectory under the `Installed/` root.
/// The cache checks whether an artifact has already been installed to avoid
/// duplicate extraction work.
///
/// ## Directory layout
///
/// ```
/// <base>/Installed/
///   <unit-id>/           ← one per runtime unit
///     ...                ← extracted archive contents or copied executable
/// ```
public struct ArtifactCache: Sendable {

    private let installedRoot: URL
    private nonisolated(unsafe) let fileManager: FileManager

    /// Creates a cache rooted at the given `Installed/` directory.
    ///
    /// - Parameter installedRoot: The root directory for installed artifacts.
    ///   Typically `HavenPaths.installedDirectory`.
    public init(
        installedRoot: URL,
        fileManager: FileManager = .default
    ) {
        self.installedRoot = installedRoot
        self.fileManager = fileManager
    }

    /// The install directory for a given runtime unit.
    ///
    /// - Parameter unitID: The runtime unit identifier.
    /// - Returns: `<installedRoot>/<unitID>/`
    public func installDirectory(for unitID: String) -> URL {
        installedRoot.appendingPathComponent(unitID, isDirectory: true)
    }

    /// Check whether an artifact is already installed for the given unit.
    ///
    /// An artifact is considered cached if its install directory exists
    /// and is non-empty.
    ///
    /// - Parameter unitID: The runtime unit identifier.
    /// - Returns: `true` if the artifact is already installed.
    public func isCached(unitID: String) -> Bool {
        let dir = installDirectory(for: unitID)
        guard fileManager.fileExists(atPath: dir.path) else {
            return false
        }
        // Check if directory has contents
        guard let contents = try? fileManager.contentsOfDirectory(atPath: dir.path) else {
            return false
        }
        return !contents.isEmpty
    }

    /// Remove a cached artifact for the given unit.
    ///
    /// - Parameter unitID: The runtime unit identifier.
    public func remove(unitID: String) throws {
        let dir = installDirectory(for: unitID)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    /// Ensure the install directory for a unit exists and is empty.
    ///
    /// Removes any existing contents and recreates the directory.
    ///
    /// - Parameter unitID: The runtime unit identifier.
    /// - Returns: The clean install directory.
    @discardableResult
    public func prepareCleanDirectory(for unitID: String) throws -> URL {
        let dir = installDirectory(for: unitID)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Atomic staging

    /// The staging directory for a given runtime unit.
    ///
    /// - Parameter unitID: The runtime unit identifier.
    /// - Returns: `<installedRoot>/<unitID>.installing/`
    public func stagingDirectory(for unitID: String) -> URL {
        installedRoot.appendingPathComponent("\(unitID).installing", isDirectory: true)
    }

    /// Prepare a clean staging directory for atomic installation.
    ///
    /// Creates `<unitID>.installing/` as a temporary workspace. Any pre-existing
    /// staging directory for this unit is removed first.
    ///
    /// - Parameter unitID: The runtime unit identifier.
    /// - Returns: The clean staging directory.
    @discardableResult
    public func prepareStagingDirectory(for unitID: String) throws -> URL {
        let dir = stagingDirectory(for: unitID)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Atomically promote a staging directory to the final install location.
    ///
    /// Removes any existing final directory, then renames the staging directory
    /// into place. This ensures the final directory is never in a partial state.
    ///
    /// - Parameter unitID: The runtime unit identifier.
    public func promoteStagingDirectory(for unitID: String) throws {
        let staging = stagingDirectory(for: unitID)
        let final_ = installDirectory(for: unitID)

        // Remove existing final directory if present
        if fileManager.fileExists(atPath: final_.path) {
            try fileManager.removeItem(at: final_)
        }

        try fileManager.moveItem(at: staging, to: final_)
    }

    /// Promote a staged update while preserving the previous install for rollback.
    ///
    /// Unlike first-time install promotion, this never deletes the existing final
    /// directory before the update is proven healthy. The previous install is
    /// moved to a unique rollback directory, then staging is moved into place.
    /// If the second move fails, the previous install is restored immediately.
    public func promoteStagingDirectoryForUpdate(
        for unitID: String
    ) throws -> (previousInstallDirectory: URL?, replacementInstallDirectory: URL) {
        let staging = stagingDirectory(for: unitID)
        let final_ = installDirectory(for: unitID)

        guard fileManager.fileExists(atPath: staging.path) else {
            throw ArtifactInstallerError.installFailed(
                unitID: unitID,
                detail: "Staging directory does not exist: \(staging.path)"
            )
        }

        try fileManager.createDirectory(at: installedRoot, withIntermediateDirectories: true)

        let previous: URL?
        if fileManager.fileExists(atPath: final_.path) {
            let rollback = installedRoot.appendingPathComponent(
                "\(unitID).rollback.\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.moveItem(at: final_, to: rollback)
            previous = rollback
        } else {
            previous = nil
        }

        do {
            try fileManager.moveItem(at: staging, to: final_)
        } catch {
            if let previous {
                try? fileManager.moveItem(at: previous, to: final_)
            }
            throw ArtifactInstallerError.installFailed(
                unitID: unitID,
                detail: "Failed to promote staged update: \(error.localizedDescription)"
            )
        }

        return (previous, final_)
    }

    /// Restore the previous install directory after a failed update.
    public func rollbackPromotedUpdate(
        for unitID: String,
        previousInstallDirectory: URL?,
        replacementInstallDirectory: URL?
    ) throws {
        let final_ = installDirectory(for: unitID)
        let replacement = replacementInstallDirectory ?? final_

        if fileManager.fileExists(atPath: replacement.path) {
            try fileManager.removeItem(at: replacement)
        }

        if let previousInstallDirectory,
           fileManager.fileExists(atPath: previousInstallDirectory.path) {
            try fileManager.moveItem(at: previousInstallDirectory, to: final_)
        }
    }

    /// Remove the preserved previous install after an update has completed.
    public func finalizePromotedUpdate(previousInstallDirectory: URL?) throws {
        guard let previousInstallDirectory,
              fileManager.fileExists(atPath: previousInstallDirectory.path)
        else { return }
        try fileManager.removeItem(at: previousInstallDirectory)
    }

    /// Remove a leftover staging directory for the given unit.
    ///
    /// - Parameter unitID: The runtime unit identifier.
    public func removeStagingDirectory(for unitID: String) {
        let dir = stagingDirectory(for: unitID)
        try? fileManager.removeItem(at: dir)
    }

    /// Clean up any stale `.installing` directories left from interrupted installs.
    public func cleanStaleStagingDirectories() throws {
        guard fileManager.fileExists(atPath: installedRoot.path) else { return }
        let contents = try fileManager.contentsOfDirectory(
            at: installedRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for item in contents where item.lastPathComponent.hasSuffix(".installing") {
            try fileManager.removeItem(at: item)
        }
    }
}
