import Foundation

/// The directory layout planned for a service under the base directory.
///
/// Layout:
/// ```
/// Services/<capability-id>/
///   data/
///   config/
///   logs/
///   run/
/// ```
public struct PlannedDirectoryLayout: Equatable, Sendable {
    /// Root of this service's directory tree.
    public let serviceRoot: URL

    /// Persistent data storage.
    public let data: URL

    /// Configuration files.
    public let config: URL

    /// Log files.
    public let logs: URL

    /// Runtime state (PID files, sockets, etc.).
    public let run: URL

    /// Derive the standard directory layout for a capability under a base directory.
    public init(baseDirectory: URL, capabilityID: String) {
        let root = baseDirectory
            .appendingPathComponent("Services")
            .appendingPathComponent(capabilityID)
        self.serviceRoot = root
        self.data = root.appendingPathComponent("data")
        self.config = root.appendingPathComponent("config")
        self.logs = root.appendingPathComponent("logs")
        self.run = root.appendingPathComponent("run")
    }

    /// All directories that should be created, in order.
    public var allDirectories: [URL] {
        [serviceRoot, data, config, logs, run]
    }
}
