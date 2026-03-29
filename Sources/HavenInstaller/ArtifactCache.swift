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
}
