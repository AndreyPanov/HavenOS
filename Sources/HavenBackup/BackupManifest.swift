import Foundation

/// Describes the contents of a Haven backup.
///
/// Written as `manifest.json` at the root of the backup destination.
/// Used during restore to detect available capabilities and verify integrity.
public struct BackupManifest: Codable, Equatable, Sendable {

    /// Manifest format version for future compatibility.
    public static let currentVersion = 1

    /// Format version of this manifest.
    public let version: Int

    /// When this backup was created.
    public let createdAt: Date

    /// The machine name where the backup was created.
    public let machineName: String

    /// Per-capability backup entries.
    public let capabilities: [CapabilityBackupEntry]

    public init(
        version: Int = BackupManifest.currentVersion,
        createdAt: Date = Date(),
        machineName: String = ProcessInfo.processInfo.hostName,
        capabilities: [CapabilityBackupEntry]
    ) {
        self.version = version
        self.createdAt = createdAt
        self.machineName = machineName
        self.capabilities = capabilities
    }

    /// The manifest file name within the backup root.
    public static let fileName = "manifest.json"
}

/// One capability's contribution to a backup.
public struct CapabilityBackupEntry: Codable, Equatable, Sendable {

    /// The capability ID (e.g. "haven.capability.kavita").
    public let capabilityID: String

    /// Human-readable name for display during restore.
    public let displayName: String

    /// The bundle ID that was installed.
    public let bundleID: String

    /// Total size in bytes of all backed-up files for this capability.
    public let totalBytes: UInt64

    /// Whether this capability's backup completed successfully.
    public let status: EntryStatus

    public init(
        capabilityID: String,
        displayName: String,
        bundleID: String,
        totalBytes: UInt64,
        status: EntryStatus = .complete
    ) {
        self.capabilityID = capabilityID
        self.displayName = displayName
        self.bundleID = bundleID
        self.totalBytes = totalBytes
        self.status = status
    }

    public enum EntryStatus: String, Codable, Sendable {
        case complete
        case partial
        case failed
    }
}

// MARK: - JSON Persistence

extension BackupManifest {

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Encode this manifest to JSON data.
    public func encode() throws -> Data {
        try Self.encoder.encode(self)
    }

    /// Decode a manifest from JSON data.
    public static func decode(from data: Data) throws -> BackupManifest {
        try Self.decoder.decode(BackupManifest.self, from: data)
    }
}
