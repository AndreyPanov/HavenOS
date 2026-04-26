import Testing
import Foundation
@testable import HavenBackup

@Suite("BackupSettings")
struct BackupSettingsTests {

    @Test("Default settings are unconfigured with weekly schedule")
    func defaults() {
        let settings = BackupSettings()
        #expect(settings.destinationPath == nil)
        #expect(settings.schedule == .weekly)
        #expect(settings.enabledCapabilities.isEmpty)
        #expect(settings.lastBackupDate == nil)
        #expect(settings.lastBackupResult == nil)
        #expect(!settings.isConfigured)
        #expect(settings.destinationURL == nil)
    }

    @Test("isConfigured is true when destination is set")
    func isConfigured() {
        let settings = BackupSettings(destinationPath: "/Volumes/Backup/Haven")
        #expect(settings.isConfigured)
        #expect(settings.destinationURL != nil)
    }

    @Test("destinationURL expands tilde")
    func tildeExpansion() {
        let settings = BackupSettings(destinationPath: "~/Backups/Haven")
        let url = settings.destinationURL
        #expect(url != nil)
        #expect(!url!.path.contains("~"))
        #expect(url!.path.hasSuffix("/Backups/Haven"))
    }

    @Test("isOverdue returns true when never backed up and schedule is not manual")
    func overdueNeverBackedUp() {
        let settings = BackupSettings(destinationPath: "/backup", schedule: .daily)
        #expect(settings.isOverdue())
    }

    @Test("isOverdue returns false for manual schedule even if never backed up")
    func manualNeverOverdue() {
        let settings = BackupSettings(destinationPath: "/backup", schedule: .manual)
        #expect(!settings.isOverdue())
    }

    @Test("isOverdue returns true when daily backup is 2 days old")
    func overdueDailyBackup() {
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        let settings = BackupSettings(
            destinationPath: "/backup",
            schedule: .daily,
            lastBackupDate: twoDaysAgo
        )
        #expect(settings.isOverdue())
    }

    @Test("isOverdue returns false when daily backup is recent")
    func notOverdueDailyBackup() {
        let oneHourAgo = Date().addingTimeInterval(-60 * 60)
        let settings = BackupSettings(
            destinationPath: "/backup",
            schedule: .daily,
            lastBackupDate: oneHourAgo
        )
        #expect(!settings.isOverdue())
    }

    @Test("isOverdue respects every3Days schedule")
    func overdueEvery3Days() {
        let fourDaysAgo = Date().addingTimeInterval(-4 * 24 * 60 * 60)
        let settings = BackupSettings(
            destinationPath: "/backup",
            schedule: .every3Days,
            lastBackupDate: fourDaysAgo
        )
        #expect(settings.isOverdue())
    }

    @Test("isOverdue respects weekly schedule")
    func notOverdueWeekly() {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        let settings = BackupSettings(
            destinationPath: "/backup",
            schedule: .weekly,
            lastBackupDate: threeDaysAgo
        )
        #expect(!settings.isOverdue())
    }

    @Test("daysSinceLastBackup is nil when never backed up")
    func daysSinceNil() {
        let settings = BackupSettings()
        #expect(settings.daysSinceLastBackup == nil)
    }

    @Test("JSON round-trip preserves all fields")
    func jsonRoundTrip() throws {
        let original = BackupSettings(
            destinationPath: "/Volumes/NAS/Haven",
            schedule: .every3Days,
            enabledCapabilities: ["haven.capability.kavita", "haven.capability.navidrome"],
            lastBackupDate: Date(timeIntervalSince1970: 1700000000),
            lastBackupResult: .partial(
                failedCapabilities: ["haven.capability.jellyfin"],
                reason: "Disk full"
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupSettings.self, from: data)

        #expect(decoded == original)
    }

    @Test("BackupResult equality works for all cases")
    func resultEquality() {
        #expect(BackupResult.success == BackupResult.success)
        #expect(BackupResult.failed(reason: "a") == BackupResult.failed(reason: "a"))
        #expect(BackupResult.failed(reason: "a") != BackupResult.failed(reason: "b"))
        #expect(
            BackupResult.partial(failedCapabilities: ["x"], reason: "r")
            == BackupResult.partial(failedCapabilities: ["x"], reason: "r")
        )
    }

    @Test("UserDefaults round-trip")
    func userDefaultsRoundTrip() {
        let defaults = UserDefaults(suiteName: "BackupSettingsTest")!
        defer { defaults.removePersistentDomain(forName: "BackupSettingsTest") }

        let original = BackupSettings(
            destinationPath: "/backup",
            schedule: .daily,
            enabledCapabilities: ["haven.capability.kavita"],
            lastBackupDate: Date(timeIntervalSince1970: 1700000000),
            lastBackupResult: .success
        )
        original.save(to: defaults)

        let loaded = BackupSettings.load(from: defaults)
        #expect(loaded.destinationPath == original.destinationPath)
        #expect(loaded.schedule == original.schedule)
        #expect(loaded.enabledCapabilities == original.enabledCapabilities)
        #expect(loaded.lastBackupResult == .success)
    }
}
