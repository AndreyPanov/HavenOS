import Foundation

/// How often Haven should automatically back up.
public enum BackupSchedule: String, Codable, Sendable, CaseIterable {
    case daily
    case weekly
    case monthly
    case manual
}

/// Persisted backup configuration.
///
/// Stored as JSON in UserDefaults. Controls where backups go,
/// how often they run, and which capabilities are included.
///
/// Each capability has its own backup destination folder, chosen by the user.
/// For example: Books → /Volumes/NAS/Books, Music → /Volumes/NAS/Music.
public struct BackupSettings: Codable, Equatable, Sendable {

    /// Per-capability backup destination paths (capability ID → absolute path).
    /// A capability appears here only after the user sets its backup folder.
    public var capabilityDestinations: [String: String]

    /// How often to run automatic backups.
    public var schedule: BackupSchedule

    /// When the last successful backup completed.
    public var lastBackupDate: Date?

    /// Result of the last backup attempt.
    public var lastBackupResult: BackupResult?

    public init(
        capabilityDestinations: [String: String] = [:],
        schedule: BackupSchedule = .weekly,
        lastBackupDate: Date? = nil,
        lastBackupResult: BackupResult? = nil
    ) {
        self.capabilityDestinations = capabilityDestinations
        self.schedule = schedule
        self.lastBackupDate = lastBackupDate
        self.lastBackupResult = lastBackupResult
    }

    /// Whether at least one capability has a backup destination configured.
    public var isConfigured: Bool {
        !capabilityDestinations.isEmpty
    }

    /// The set of capability IDs that have backup configured.
    public var configuredCapabilities: Set<String> {
        Set(capabilityDestinations.keys)
    }

    /// Get the destination URL for a specific capability, or nil.
    public func destinationURL(for capabilityID: String) -> URL? {
        guard let path = capabilityDestinations[capabilityID] else { return nil }
        let expanded = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    /// Set the backup destination for a capability.
    public mutating func setDestination(_ path: String, for capabilityID: String) {
        capabilityDestinations[capabilityID] = path
    }

    /// Remove the backup destination for a capability.
    public mutating func removeDestination(for capabilityID: String) {
        capabilityDestinations.removeValue(forKey: capabilityID)
    }

    /// Whether a backup is due based on schedule and last backup date.
    public func isOverdue(now: Date = Date()) -> Bool {
        guard isConfigured else { return false }
        guard schedule != .manual else { return false }
        guard let last = lastBackupDate else { return true }

        let interval: TimeInterval = switch schedule {
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        case .monthly: 30 * 24 * 60 * 60
        case .manual: .infinity
        }

        return now.timeIntervalSince(last) >= interval
    }

    /// Number of days since the last successful backup, or nil if never backed up.
    public var daysSinceLastBackup: Int? {
        guard let last = lastBackupDate else { return nil }
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day
    }
}

/// Outcome of a backup attempt.
public enum BackupResult: Codable, Equatable, Sendable {
    /// All capabilities backed up successfully.
    case success
    /// Some capabilities backed up, others failed.
    case partial(failedCapabilities: [String], reason: String)
    /// Backup failed entirely.
    case failed(reason: String)
}

// MARK: - UserDefaults persistence

extension BackupSettings {

    private static let defaultsKey = "haven.backup.settings"

    /// Load settings from UserDefaults. Returns default settings if none saved.
    public static func load(from defaults: UserDefaults = .standard) -> BackupSettings {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return BackupSettings()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(BackupSettings.self, from: data)) ?? BackupSettings()
    }

    /// Save settings to UserDefaults.
    public func save(to defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
