import Testing
import Foundation
@testable import HavenBackup

@Suite("BackupManifest")
struct BackupManifestTests {

    @Test("Manifest JSON round-trip preserves all fields")
    func jsonRoundTrip() throws {
        let manifest = BackupManifest(
            createdAt: Date(timeIntervalSince1970: 1700000000),
            machineName: "test-mac",
            capabilities: [
                CapabilityBackupEntry(
                    capabilityID: "haven.capability.kavita",
                    displayName: "Books",
                    bundleID: "haven.bundle.kavita",
                    relativePaths: ["Books/data", "Books/config"],
                    totalBytes: 1_048_576,
                    status: .complete
                ),
                CapabilityBackupEntry(
                    capabilityID: "haven.capability.navidrome",
                    displayName: "Music",
                    bundleID: "haven.bundle.navidrome",
                    relativePaths: ["Music/data", "Music/config"],
                    totalBytes: 2_097_152,
                    status: .complete
                ),
            ],
            includesCredentials: true,
            includesState: true
        )

        let data = try manifest.encode()
        let decoded = try BackupManifest.decode(from: data)

        #expect(decoded == manifest)
    }

    @Test("Manifest version is current")
    func manifestVersion() {
        let manifest = BackupManifest(capabilities: [])
        #expect(manifest.version == BackupManifest.currentVersion)
        #expect(manifest.version == 1)
    }

    @Test("Manifest fileName is manifest.json")
    func fileName() {
        #expect(BackupManifest.fileName == "manifest.json")
    }

    @Test("Empty capabilities list round-trips")
    func emptyCapabilities() throws {
        let manifest = BackupManifest(
            createdAt: Date(timeIntervalSince1970: 1700000000),
            machineName: "test",
            capabilities: []
        )

        let data = try manifest.encode()
        let decoded = try BackupManifest.decode(from: data)

        #expect(decoded.capabilities.isEmpty)
        #expect(decoded.includesCredentials)
        #expect(decoded.includesState)
    }

    @Test("Entry status values encode correctly")
    func entryStatus() throws {
        let entries: [CapabilityBackupEntry] = [
            CapabilityBackupEntry(
                capabilityID: "a", displayName: "A", bundleID: "b",
                relativePaths: [], totalBytes: 0, status: .complete
            ),
            CapabilityBackupEntry(
                capabilityID: "b", displayName: "B", bundleID: "b",
                relativePaths: [], totalBytes: 0, status: .partial
            ),
            CapabilityBackupEntry(
                capabilityID: "c", displayName: "C", bundleID: "b",
                relativePaths: [], totalBytes: 0, status: .failed
            ),
        ]

        let manifest = BackupManifest(
            createdAt: Date(timeIntervalSince1970: 1700000000),
            machineName: "test",
            capabilities: entries
        )

        let data = try manifest.encode()
        let decoded = try BackupManifest.decode(from: data)

        #expect(decoded.capabilities[0].status == .complete)
        #expect(decoded.capabilities[1].status == .partial)
        #expect(decoded.capabilities[2].status == .failed)
    }

    @Test("Manifest JSON contains expected keys")
    func jsonStructure() throws {
        let manifest = BackupManifest(
            createdAt: Date(timeIntervalSince1970: 1700000000),
            machineName: "test",
            capabilities: [
                CapabilityBackupEntry(
                    capabilityID: "haven.capability.kavita",
                    displayName: "Books",
                    bundleID: "haven.bundle.kavita",
                    relativePaths: ["Books/data"],
                    totalBytes: 100
                ),
            ]
        )

        let data = try manifest.encode()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["version"] as? Int == 1)
        #expect(json["machineName"] as? String == "test")
        #expect(json["includesCredentials"] as? Bool == true)
        #expect(json["includesState"] as? Bool == true)

        let caps = json["capabilities"] as? [[String: Any]]
        #expect(caps?.count == 1)
        #expect(caps?[0]["capabilityID"] as? String == "haven.capability.kavita")
        #expect(caps?[0]["displayName"] as? String == "Books")
    }
}
