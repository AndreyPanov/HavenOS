import Foundation

/// The directory tree for one installed capability under the services root.
///
/// Layout:
/// ```
/// Services/<capability-id>/
///   data/
///   config/
///   logs/
///   run/
/// ```
///
/// This is a value type. It computes paths but does not touch the filesystem.
public struct ServiceDirectoryLayout: Codable, Equatable, Sendable {

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

    /// Derive the standard layout for a capability under the given services directory.
    public init(servicesDirectory: URL, capabilityID: String) {
        let root = servicesDirectory.appendingPathComponent(capabilityID)
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
