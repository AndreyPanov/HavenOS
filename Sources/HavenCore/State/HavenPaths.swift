import Foundation

/// Resolves all major directory and file paths from a single base directory.
///
/// Layout under the base directory:
/// ```
/// State/
///   services.json
/// Downloads/
/// Installed/<runtime-unit-id>/
/// Services/<capability-id>/
///   data/
///   config/
///   logs/
///   run/
/// ```
///
/// `HavenPaths` is a pure value type — it computes paths but does not
/// create directories or touch the filesystem.
public struct HavenPaths: Equatable, Sendable {

    /// The root directory from which all other paths are derived.
    public let base: URL

    public init(base: URL) {
        self.base = base
    }

    // MARK: - Top-level directories

    /// `<base>/State/` — persistent state files.
    public var stateDirectory: URL {
        base.appendingPathComponent("State")
    }

    /// `<base>/Downloads/` — temporary download staging area.
    public var downloadsDirectory: URL {
        base.appendingPathComponent("Downloads")
    }

    /// `<base>/Installed/` — extracted artifacts, one subdirectory per runtime unit.
    public var installedDirectory: URL {
        base.appendingPathComponent("Installed")
    }

    /// `<base>/Services/` — root of all per-capability service directories.
    public var servicesDirectory: URL {
        base.appendingPathComponent("Services")
    }

    // MARK: - State files

    /// `<base>/State/services.json` — the main state file.
    public var stateFile: URL {
        stateDirectory.appendingPathComponent("services.json")
    }

    // MARK: - Per-service directories

    /// Returns the ``ServiceDirectoryLayout`` for a given capability ID.
    public func serviceLayout(for capabilityID: String) -> ServiceDirectoryLayout {
        ServiceDirectoryLayout(servicesDirectory: servicesDirectory, capabilityID: capabilityID)
    }

    // MARK: - All top-level directories

    /// The top-level directories that should exist under the base.
    public var topLevelDirectories: [URL] {
        [stateDirectory, downloadsDirectory, installedDirectory, servicesDirectory]
    }
}
