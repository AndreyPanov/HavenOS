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
        let settings = BackupSettings(
            capabilityDestinations: ["haven.capability.kavita": "/backup/books"],
            schedule: .daily
        )
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
            capabilityDestinations: [
                "haven.capability.kavita": "/backup/books",
                "haven.capability.navidrome": "/backup/music",
                "haven.capability.jellyfin": "/backup/movies",
            ],
            schedule: .weekly,
            lastBackupDate: Date().addingTimeInterval(-24 * 60 * 60),
            lastBackupResult: .success
        )

        let manifests: [String: BackupManifest] = [
            "haven.capability.kavita": BackupManifest(
                createdAt: Date().addingTimeInterval(-24 * 60 * 60), machineName: "test",
                capabilities: [CapabilityBackupEntry(capabilityID: "haven.capability.kavita", displayName: "Books", bundleID: "b", totalBytes: 0)]
            ),
            "haven.capability.navidrome": BackupManifest(
                createdAt: Date().addingTimeInterval(-24 * 60 * 60), machineName: "test",
                capabilities: [CapabilityBackupEntry(capabilityID: "haven.capability.navidrome", displayName: "Music", bundleID: "b", totalBytes: 0)]
            ),
            "haven.capability.jellyfin": BackupManifest(
                createdAt: Date().addingTimeInterval(-24 * 60 * 60), machineName: "test",
                capabilities: [CapabilityBackupEntry(capabilityID: "haven.capability.jellyfin", displayName: "Movies", bundleID: "b", totalBytes: 0)]
            ),
        ]

        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: testCapabilities,
            manifests: manifests
        )

        #expect(health.status == .healthy)
        #expect(health.protectionScore == 100)
        #expect(health.capabilities.allSatisfy { $0.isProtected })
    }

    @Test("Partial backup shows correct protection score")
    func partialProtection() {
        let settings = BackupSettings(
            capabilityDestinations: [
                "haven.capability.kavita": "/backup/books",
                "haven.capability.navidrome": "/backup/music",
            ],
            schedule: .weekly,
            lastBackupDate: Date(),
            lastBackupResult: .success
        )

        let manifests: [String: BackupManifest] = [
            "haven.capability.kavita": BackupManifest(
                createdAt: Date(), machineName: "test",
                capabilities: [CapabilityBackupEntry(capabilityID: "haven.capability.kavita", displayName: "Books", bundleID: "b", totalBytes: 0, status: .complete)]
            ),
            "haven.capability.navidrome": BackupManifest(
                createdAt: Date(), machineName: "test",
                capabilities: [CapabilityBackupEntry(capabilityID: "haven.capability.navidrome", displayName: "Music", bundleID: "b", totalBytes: 0, status: .failed)]
            ),
        ]

        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: testCapabilities,
            manifests: manifests
        )

        // 1 out of 3 protected (kavita complete, navidrome failed, jellyfin not configured)
        #expect(health.protectionScore == 33)

        let kavita = health.capabilities.first { $0.capabilityID == "haven.capability.kavita" }
        #expect(kavita?.isProtected == true)
        #expect(kavita?.destinationPath == "/backup/books")

        let navidrome = health.capabilities.first { $0.capabilityID == "haven.capability.navidrome" }
        #expect(navidrome?.isProtected == false)

        let jellyfin = health.capabilities.first { $0.capabilityID == "haven.capability.jellyfin" }
        #expect(jellyfin?.isProtected == false)
        #expect(jellyfin?.destinationPath == nil) // not configured
    }

    @Test("Overdue backup shows overdue status")
    func overdueBackup() {
        let tenDaysAgo = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        let settings = BackupSettings(
            capabilityDestinations: ["cap": "/backup"],
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
            capabilityDestinations: ["cap": "/backup"],
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
            capabilityDestinations: ["cap": "/backup"],
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
        let settings = BackupSettings(capabilityDestinations: ["cap": "/backup"])
        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: []
        )

        #expect(health.protectionScore == 0)
        #expect(health.capabilities.isEmpty)
    }

    @Test("Destination path is shown per capability")
    func destinationPerCapability() {
        let settings = BackupSettings(
            capabilityDestinations: [
                "haven.capability.kavita": "/Volumes/NAS/Books",
                "haven.capability.navidrome": "/Volumes/NAS/Music",
            ]
        )
        let health = BackupHealth.compute(
            settings: settings,
            installedCapabilities: testCapabilities
        )

        let kavita = health.capabilities.first { $0.capabilityID == "haven.capability.kavita" }
        #expect(kavita?.destinationPath == "/Volumes/NAS/Books")

        let music = health.capabilities.first { $0.capabilityID == "haven.capability.navidrome" }
        #expect(music?.destinationPath == "/Volumes/NAS/Music")

        let movies = health.capabilities.first { $0.capabilityID == "haven.capability.jellyfin" }
        #expect(movies?.destinationPath == nil)
    }
}
