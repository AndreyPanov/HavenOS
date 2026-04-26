import Foundation

/// How often Haven should automatically back up.
public enum BackupSchedule: String, Codable, Sendable, CaseIterable {
    case daily
    case every3Days
    case weekly
    case manual
}

/// Persisted backup configuration.
///
/// Stored as JSON in UserDefaults. Controls where backups go,
/// how often they run, and which capabilities are included.
public struct BackupSettings: Codable, Equatable, Sendable {

    /// Absolute path to the backup destination folder.
    /// Nil means backup has not been configured yet.
    public var destinationPath: String?

    /// How often to run automatic backups.
    public var schedule: BackupSchedule

    /// Capability IDs that are included in backup.
    /// Empty means "back up everything installed."
    public var enabledCapabilities: Set<String>

    /// When the last successful backup completed.
    public var lastBackupDate: Date?

    /// Result of the last backup attempt.
    public var lastBackupResult: BackupResult?

    public init(
        destinationPath: String? = nil,
        schedule: BackupSchedule = .weekly,
        enabledCapabilities: Set<String> = [],
        lastBackupDate: Date? = nil,
        lastBackupResult: BackupResult? = nil
    ) {
        self.destinationPath = destinationPath
        self.schedule = schedule
        self.enabledCapabilities = enabledCapabilities
        self.lastBackupDate = lastBackupDate
        self.lastBackupResult = lastBackupResult
    }

    /// Whether backup has been configured with a valid destination.
    public var isConfigured: Bool {
        destinationPath != nil
    }

    /// The destination as a file URL, or nil if not configured.
    public var destinationURL: URL? {
        guard let path = destinationPath else { return nil }
        let expanded = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    /// Whether a backup is due based on schedule and last backup date.
    public func isOverdue(now: Date = Date()) -> Bool {
        guard schedule != .manual else { return false }
        guard let last = lastBackupDate else { return true }

        let interval: TimeInterval = switch schedule {
        case .daily: 24 * 60 * 60
        case .every3Days: 3 * 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
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
