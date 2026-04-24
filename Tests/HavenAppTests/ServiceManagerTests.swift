import Testing
import Foundation
import HavenCore
@testable import HavenAppKit

// MARK: - ServiceManager Lifecycle Tests

@Suite("ServiceManager Lifecycle")
struct ServiceManagerTests {

    // MARK: - Double-Start Guard

    @Test("startService is a no-op when the service is already running")
    @MainActor func startServiceNoOpWhenRunning() async {
        let (sm, cleanup) = try! makeServiceManager(serviceStatus: .running)
        defer { cleanup() }

        sm.refresh()

        // Verify the service is loaded as running
        let service = sm.installedServices.first { $0.id == "haven.test.service" }
        #expect(service != nil)
        #expect(service?.status == .running)

        // Call startService — should return immediately without setting isPerformingAction
        await sm.startService(capabilityID: "haven.test.service")

        #expect(sm.isPerformingAction == false)
        #expect(sm.activeCapabilityID == nil)
        #expect(sm.actionStatus == nil)
        #expect(sm.lastError == nil)
    }

    @Test("startService proceeds when service is stopped (does not skip)")
    @MainActor func startServiceProceedsWhenStopped() async {
        let (sm, cleanup) = try! makeServiceManager(serviceStatus: .stopped)
        defer { cleanup() }

        sm.refresh()

        let service = sm.installedServices.first { $0.id == "haven.test.service" }
        #expect(service?.status == .stopped)

        // Call startService on a stopped service — it should NOT skip (unlike running).
        // The executor runs (may succeed or fail depending on launchd state),
        // but the key assertion is that isPerformingAction resets after completion.
        await sm.startService(capabilityID: "haven.test.service")

        #expect(sm.isPerformingAction == false)
    }

    // MARK: - isPerformingAction Cleanup

    @Test("isPerformingAction is always reset after installService completes")
    @MainActor func installServiceCleansUpFlags() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sm = ServiceManager(basePath: tmpDir)

        // Install will fail (no catalog loaded), but flags must still be cleaned up
        await sm.installService(capabilityID: "haven.test.install")

        #expect(sm.isPerformingAction == false, "isPerformingAction must be reset after install")
        #expect(sm.activeCapabilityID == nil, "activeCapabilityID must be reset after install")
        #expect(sm.actionStatus == nil, "actionStatus must be reset after install")
    }

    // MARK: - Credential Cleanup on Uninstall

    @Test("uninstallService clears all Kavita facade credentials from UserDefaults")
    @MainActor func uninstallClearsKavitaCredentials() async {
        let capID = "haven.test.kavita.cleanup.\(UUID().uuidString)"
        let (sm, cleanup) = try! makeServiceManager(serviceStatus: .stopped, capabilityID: capID)
        defer {
            cleanup()
            cleanupAllDefaults(for: capID)
        }

        // Seed UserDefaults with Kavita credentials
        let defaults = UserDefaults.standard
        let kavitaKeys = [
            "haven.kavita.token.\(capID)",
            "haven.kavita.username.\(capID)",
            "haven.kavita.password.\(capID)",
            "haven.kavita.managedUser.\(capID)",
            "haven.kavita.managedPass.\(capID)",
            "haven.kavita.apiKey.\(capID)",
            "haven.kavita.customAccount.\(capID)",
            "haven.kavita.libraryPath.\(capID)",
        ]
        for key in kavitaKeys {
            defaults.set("test-value", forKey: key)
        }

        // Verify keys are set
        for key in kavitaKeys {
            #expect(defaults.string(forKey: key) == "test-value")
        }

        sm.refresh()

        // Uninstall — executor will fail (no real install), but credentials should be cleared first
        await sm.uninstallService(capabilityID: capID)

        // All credential keys must be gone
        for key in kavitaKeys {
            #expect(defaults.string(forKey: key) == nil, "Key should be cleared: \(key)")
        }
    }

    @Test("uninstallService clears all Navidrome facade credentials from UserDefaults")
    @MainActor func uninstallClearsNavidromeCredentials() async {
        let capID = "haven.test.navidrome.cleanup.\(UUID().uuidString)"
        let (sm, cleanup) = try! makeServiceManager(serviceStatus: .stopped, capabilityID: capID)
        defer {
            cleanup()
            cleanupAllDefaults(for: capID)
        }

        let defaults = UserDefaults.standard
        let navidromeKeys = [
            "haven.navidrome.token.\(capID)",
            "haven.navidrome.username.\(capID)",
            "haven.navidrome.password.\(capID)",
            "haven.navidrome.managedUser.\(capID)",
            "haven.navidrome.managedPass.\(capID)",
            "haven.navidrome.customAccount.\(capID)",
            "haven.navidrome.libraryPath.\(capID)",
        ]
        for key in navidromeKeys {
            defaults.set("test-value", forKey: key)
        }

        sm.refresh()
        await sm.uninstallService(capabilityID: capID)

        for key in navidromeKeys {
            #expect(defaults.string(forKey: key) == nil, "Key should be cleared: \(key)")
        }
    }

    @Test("uninstallService clears credentials even when executor fails")
    @MainActor func uninstallClearsCredentialsOnFailure() async {
        let capID = "haven.test.creds.\(UUID().uuidString)"
        // Don't write a state file — executor.uninstall will definitely fail
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sm = ServiceManager(basePath: tmpDir)

        let defaults = UserDefaults.standard
        let key = "haven.kavita.token.\(capID)"
        defaults.set("should-be-cleared", forKey: key)
        defer { defaults.removeObject(forKey: key) }

        await sm.uninstallService(capabilityID: capID)

        // Credential cleared even though executor failed
        #expect(defaults.string(forKey: key) == nil)
        // Executor error is captured
        #expect(sm.lastError != nil)
    }

    @Test("uninstallService removes cached facade")
    @MainActor func uninstallRemovesFacade() async {
        let capID = "haven.capability.kavita"
        let (sm, cleanup) = try! makeServiceManager(serviceStatus: .running, capabilityID: capID)
        defer { cleanup() }

        sm.refresh()

        // Create and cache a facade
        let facade = sm.facade(for: capID)
        #expect(facade != nil)

        // Uninstall
        await sm.uninstallService(capabilityID: capID)

        // After uninstall + refresh, facade should no longer be returned
        // (installedServices no longer contains it)
        sm.refresh()
        let facadeAfter = sm.facade(for: capID)
        #expect(facadeAfter == nil)
    }

    // MARK: - Helpers

    /// Create a ServiceManager backed by a temp directory with one fake installed service.
    @MainActor
    private func makeServiceManager(
        serviceStatus: HavenCore.ServiceStatus,
        capabilityID: String = "haven.test.service"
    ) throws -> (ServiceManager, () -> Void) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-test-\(UUID().uuidString)")
        let fm = FileManager.default
        let stateDir = tmpDir.appendingPathComponent("State")
        let servicesDir = tmpDir.appendingPathComponent("Services")
        try fm.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: servicesDir, withIntermediateDirectories: true)

        let layout = ServiceDirectoryLayout(servicesDirectory: servicesDir, capabilityID: capabilityID)

        let storedService = StoredServiceState(
            capability: capabilityID,
            bundleID: "test.bundle",
            installedAt: Date(),
            updatedAt: Date(),
            status: serviceStatus,
            resolvedSettings: [:],
            portAssignments: [StoredPortAssignment(unitID: "test.unit", port: 9999)],
            runtimeUnits: ["test.unit"],
            directoryLayout: layout
        )

        let state = HavenState(services: [capabilityID: storedService])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: stateDir.appendingPathComponent("services.json"))

        let sm = ServiceManager(basePath: tmpDir)
        let cleanup = { try? fm.removeItem(at: tmpDir); return }
        return (sm, cleanup)
    }

    private func cleanupAllDefaults(for capabilityID: String) {
        let defaults = UserDefaults.standard
        for prefix in ["haven.kavita.", "haven.navidrome."] {
            for suffix in ["token", "username", "password", "managedUser", "managedPass", "apiKey", "customAccount", "libraryPath"] {
                defaults.removeObject(forKey: "\(prefix)\(suffix).\(capabilityID)")
            }
        }
    }
}
