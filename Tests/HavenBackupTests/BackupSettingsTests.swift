import Testing
import Foundation
@testable import HavenBackup

@Suite("BackupSettings")
struct BackupSettingsTests {

    @Test("Default settings are unconfigured with weekly schedule")
    func defaults() {
        let settings = BackupSettings()
        #expect(settings.capabilityDestinations.isEmpty)
        #expect(settings.schedule == .weekly)
        #expect(settings.lastBackupDate == nil)
        #expect(settings.lastBackupResult == nil)
        #expect(!settings.isConfigured)
        #expect(settings.configuredCapabilities.isEmpty)
    }

    @Test("isConfigured is true when at least one capability has a destination")
    func isConfigured() {
        var settings = BackupSettings()
        settings.setDestination("/Volumes/NAS/Books", for: "haven.capability.kavita")
        #expect(settings.isConfigured)
        #expect(settings.configuredCapabilities.count == 1)
    }

    @Test("destinationURL expands tilde for capability")
    func tildeExpansion() {
        var settings = BackupSettings()
        settings.setDestination("~/Backups/Books", for: "haven.capability.kavita")
        let url = settings.destinationURL(for: "haven.capability.kavita")
        #expect(url != nil)
        #expect(!url!.path.contains("~"))
        #expect(url!.path.hasSuffix("/Backups/Books"))
    }

    @Test("destinationURL returns nil for unconfigured capability")
    func destinationNil() {
        let settings = BackupSettings()
        #expect(settings.destinationURL(for: "haven.capability.kavita") == nil)
    }

    @Test("setDestination and removeDestination work")
    func setAndRemove() {
        var settings = BackupSettings()
        settings.setDestination("/backup/books", for: "haven.capability.kavita")
        #expect(settings.capabilityDestinations["haven.capability.kavita"] == "/backup/books")

        settings.removeDestination(for: "haven.capability.kavita")
        #expect(settings.capabilityDestinations["haven.capability.kavita"] == nil)
        #expect(!settings.isConfigured)
    }

    @Test("isOverdue returns false when not configured")
    func overdueNotConfigured() {
        let settings = BackupSettings(schedule: .daily)
        #expect(!settings.isOverdue())
    }

    @Test("isOverdue returns true when configured and never backed up")
    func overdueNeverBackedUp() {
        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .daily
        )
        #expect(settings.isOverdue())
    }

    @Test("isOverdue returns false for manual schedule even if never backed up")
    func manualNeverOverdue() {
        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .manual
        )
        #expect(!settings.isOverdue())
    }

    @Test("isOverdue returns true when daily backup is 2 days old")
    func overdueDailyBackup() {
        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .daily,
            lastBackupDate: twoDaysAgo
        )
        #expect(settings.isOverdue())
    }

    @Test("isOverdue returns false when daily backup is recent")
    func notOverdueDailyBackup() {
        let oneHourAgo = Date().addingTimeInterval(-60 * 60)
        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .daily,
            lastBackupDate: oneHourAgo
        )
        #expect(!settings.isOverdue())
    }

    @Test("isOverdue respects every3Days schedule")
    func overdueEvery3Days() {
        let fourDaysAgo = Date().addingTimeInterval(-4 * 24 * 60 * 60)
        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
            schedule: .every3Days,
            lastBackupDate: fourDaysAgo
        )
        #expect(settings.isOverdue())
    }

    @Test("isOverdue respects weekly schedule")
    func notOverdueWeekly() {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 24 * 60 * 60)
        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
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
            capabilityDestinations: [
                "haven.capability.kavita": "/Volumes/NAS/Books",
                "haven.capability.navidrome": "/Volumes/NAS/Music",
            ],
            schedule: .every3Days,
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
            capabilityDestinations: ["haven.capability.kavita": "/backup/books"],
            schedule: .daily,
            lastBackupDate: Date(timeIntervalSince1970: 1700000000),
            lastBackupResult: .success
        )
        original.save(to: defaults)

        let loaded = BackupSettings.load(from: defaults)
        #expect(loaded.capabilityDestinations == original.capabilityDestinations)
        #expect(loaded.schedule == original.schedule)
        #expect(loaded.lastBackupResult == .success)
    }

    @Test("Multiple capabilities can have different destinations")
    func multipleDestinations() {
        var settings = BackupSettings()
        settings.setDestination("/nas/books", for: "haven.capability.kavita")
        settings.setDestination("/nas/music", for: "haven.capability.navidrome")
        settings.setDestination("/nas/movies", for: "haven.capability.jellyfin")

        #expect(settings.configuredCapabilities.count == 3)
        #expect(settings.destinationURL(for: "haven.capability.kavita")?.path == "/nas/books")
        #expect(settings.destinationURL(for: "haven.capability.navidrome")?.path == "/nas/music")
        #expect(settings.destinationURL(for: "haven.capability.jellyfin")?.path == "/nas/movies")
    }
}
