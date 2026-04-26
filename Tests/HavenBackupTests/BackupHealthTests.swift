import Testing
import Foundation
@testable import HavenBackup

@Suite("BackupHealth")
struct BackupHealthTests {

    private let testCapabilities: [(id: String, name: String)] = [
        (id: "haven.capability.kavita", name: "Books"),
        (id: "haven.capability.navidrome", name: "Music"),
        (id: "haven.capability.jellyfin", name: "Movies"),
    ]

    @Test("Not configured shows 0% protection")
    func notConfigured() {
        let health = BackupHealth.compute(
            settings: BackupSettings(),
            installedCapabilities: testCapabilities
        )

        #expect(health.status == .notConfigured)
        #expect(health.protectionScore == 0)
        #expect(health.capabilities.count == 3)
        #expect(health.capabilities.allSatisfy { !$0.isProtected })
    }

    @Test("Never run shows neverRun status")
    func neverRun() {
        let settings = BackupSettings(destinationPath: "/backup", schedule: .daily)
        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: testCapabilities
        )

        #expect(health.status == .neverRun)
        #expect(health.protectionScore == 0)
    }

    @Test("Successful backup shows healthy status and 100% when all backed up")
    func healthyFullBackup() {
        let settings = BackupSettings(
            destinationPath: "/backup",
            schedule: .weekly,
            lastBackupDate: Date().addingTimeInterval(-24 * 60 * 60),
            lastBackupResult: .success
        )

        let manifest = BackupManifest(
            createdAt: Date().addingTimeInterval(-24 * 60 * 60),
            machineName: "test",
            capabilities: [
                CapabilityBackupEntry(capabilityID: "haven.capability.kavita", displayName: "Books", bundleID: "b", relativePaths: [], totalBytes: 0),
                CapabilityBackupEntry(capabilityID: "haven.capability.navidrome", displayName: "Music", bundleID: "b", relativePaths: [], totalBytes: 0),
                CapabilityBackupEntry(capabilityID: "haven.capability.jellyfin", displayName: "Movies", bundleID: "b", relativePaths: [], totalBytes: 0),
            ]
        )

        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: testCapabilities,
            manifest: manifest
        )

        #expect(health.status == .healthy)
        #expect(health.protectionScore == 100)
        #expect(health.capabilities.allSatisfy { $0.isProtected })
    }

    @Test("Partial backup shows correct protection score")
    func partialProtection() {
        let settings = BackupSettings(
            destinationPath: "/backup",
            schedule: .weekly,
            lastBackupDate: Date(),
            lastBackupResult: .success
        )

        let manifest = BackupManifest(
            createdAt: Date(),
            machineName: "test",
            capabilities: [
                CapabilityBackupEntry(capabilityID: "haven.capability.kavita", displayName: "Books", bundleID: "b", relativePaths: [], totalBytes: 0, status: .complete),
                CapabilityBackupEntry(capabilityID: "haven.capability.navidrome", displayName: "Music", bundleID: "b", relativePaths: [], totalBytes: 0, status: .failed),
            ]
        )

        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: testCapabilities,
            manifest: manifest
        )

        // 1 out of 3 protected (only kavita complete, navidrome failed, jellyfin not in manifest)
        #expect(health.protectionScore == 33)

        let kavita = health.capabilities.first { $0.capabilityID == "haven.capability.kavita" }
        #expect(kavita?.isProtected == true)

        let navidrome = health.capabilities.first { $0.capabilityID == "haven.capability.navidrome" }
        #expect(navidrome?.isProtected == false) // failed entry is not protected

        let jellyfin = health.capabilities.first { $0.capabilityID == "haven.capability.jellyfin" }
        #expect(jellyfin?.isProtected == false)
    }

    @Test("Overdue backup shows overdue status")
    func overdueBackup() {
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        let settings = BackupSettings(
            destinationPath: "/backup",
            schedule: .weekly,
            lastBackupDate: tenDaysAgo,
            lastBackupResult: .success
        )

        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: testCapabilities
        )

        if case .overdue(let days) = health.status {
            #expect(days >= 9)
        } else {
            Issue.record("Expected .overdue status, got \(health.status)")
        }
    }

    @Test("Failed backup shows failed status")
    func failedBackup() {
        let settings = BackupSettings(
            destinationPath: "/backup",
            schedule: .daily,
            lastBackupDate: Date(),
            lastBackupResult: .failed(reason: "NAS unavailable")
        )

        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: testCapabilities
        )

        if case .failed(let message) = health.status {
            #expect(message == "NAS unavailable")
        } else {
            Issue.record("Expected .failed status")
        }
    }

    @Test("Warning status from partial result")
    func warningStatus() {
        let settings = BackupSettings(
            destinationPath: "/backup",
            schedule: .daily,
            lastBackupDate: Date(),
            lastBackupResult: .partial(failedCapabilities: ["jellyfin"], reason: "Disk full")
        )

        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: testCapabilities
        )

        if case .warning(let message) = health.status {
            #expect(message == "Disk full")
        } else {
            Issue.record("Expected .warning status")
        }
    }

    @Test("No installed capabilities yields 0% protection score")
    func noCapabilities() {
        let settings = BackupSettings(destinationPath: "/backup")
        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: []
        )

        #expect(health.protectionScore == 0)
        #expect(health.capabilities.isEmpty)
    }

    @Test("Destination is passed through to health")
    func destinationPassthrough() {
        let settings = BackupSettings(destinationPath: "/Volumes/NAS/Haven")
        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: testCapabilities
        )

        #expect(health.destination == "/Volumes/NAS/Haven")
    }
}
