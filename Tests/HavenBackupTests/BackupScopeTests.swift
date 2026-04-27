import Testing
import Foundation
@testable import HavenBackup
@testable import HavenCore

@Suite("BackupScope")
struct BackupScopeTests {

    private let baseURL = URL(fileURLWithPath: "/tmp/haven-test")

    private func makeState(
        capability: String = "haven.capability.kavita",
        bundleID: String = "haven.bundle.kavita",
        resolvedSettings: [String: String] = [:]
    ) -> StoredServiceState {
        let layout = ServiceDirectoryLayout(
            servicesDirectory: baseURL.appendingPathComponent("Services"),
            capabilityID: capability
        )
        return StoredServiceState(
            capability: capability,
            bundleID: bundleID,
            installedAt: Date(),
            updatedAt: Date(),
            status: .running,
            resolvedSettings: resolvedSettings,
            portAssignments: [],
            runtimeUnits: ["unit1"],
            directoryLayout: layout
        )
    }

    @Test("Scope without content settings has empty contentPaths")
    func noContentPaths() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState())

        #expect(result.contentPaths.isEmpty)
    }

    @Test("Content path from library_path setting is included")
    func contentPathFromSettings() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            resolvedSettings: ["library_path": "/Users/test/Books"]
        ))

        #expect(result.contentPaths.count == 1)
        #expect(result.contentPaths[0].path == "/Users/test/Books")
    }

    @Test("Content path from music_path setting is included")
    func musicPathFromSettings() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            capability: "haven.capability.navidrome",
            bundleID: "haven.bundle.navidrome",
            resolvedSettings: ["music_path": "/Users/test/Music"]
        ))

        #expect(result.contentPaths.count == 1)
        #expect(result.contentPaths[0].path == "/Users/test/Music")
    }

    @Test("Content path from movies_path setting is included")
    func moviesPathFromSettings() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            capability: "haven.capability.jellyfin",
            bundleID: "haven.bundle.jellyfin",
            resolvedSettings: ["movies_path": "/Users/test/Movies"]
        ))

        #expect(result.contentPaths.count == 1)
        #expect(result.contentPaths[0].path == "/Users/test/Movies")
    }

    @Test("Tilde in content path is expanded")
    func tildeExpansion() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            resolvedSettings: ["library_path": "~/Books"]
        ))

        #expect(result.contentPaths.count == 1)
        #expect(!result.contentPaths[0].path.contains("~"))
    }

    @Test("Bundle storage policy adds userVisible dirs to content")
    func storagePolicyUserVisible() {
        let scope = BackupScope()
        let bundle = HavenCore.Bundle(
            id: "haven.bundle.kavita",
            name: "Kavita",
            capability: "haven.capability.kavita",
            storage: [
                "content": StoragePolicy(persistent: true, userVisible: true),
                "config": StoragePolicy(persistent: true, userVisible: false),
            ]
        )
        let result = scope.scope(for: makeState(), bundle: bundle)

        let contentNames = result.contentPaths.map(\.lastPathComponent)
        #expect(contentNames.contains("content"))
    }

    @Test("Non-userVisible storage policies are not included")
    func nonUserVisibleExcluded() {
        let scope = BackupScope()
        let bundle = HavenCore.Bundle(
            id: "haven.bundle.test",
            name: "Test",
            capability: "haven.capability.test",
            storage: [
                "cache": StoragePolicy(persistent: true, userVisible: false),
                "data": StoragePolicy(persistent: true, userVisible: false),
            ]
        )
        let state = makeState(capability: "haven.capability.test", bundleID: "haven.bundle.test")
        let result = scope.scope(for: state, bundle: bundle)

        #expect(result.contentPaths.isEmpty)
    }

    @Test("scopeAll returns sorted results for multiple capabilities")
    func scopeAllSorted() {
        let scope = BackupScope()

        let stateA = makeState(capability: "haven.capability.navidrome", bundleID: "b")
        let stateB = makeState(capability: "haven.capability.kavita", bundleID: "b")

        let services = [stateA.capability: stateA, stateB.capability: stateB]
        let results = scope.scopeAll(services: services)

        #expect(results.count == 2)
        #expect(results[0].capabilityID == "haven.capability.kavita")
        #expect(results[1].capabilityID == "haven.capability.navidrome")
    }

    @Test("Scope without bundle has no content paths")
    func scopeWithoutBundle() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(), bundle: nil)

        #expect(result.contentPaths.isEmpty)
    }

    @Test("No duplicate paths when setting and policy both resolve to same content dir")
    func noDuplicateContentPaths() {
        let scope = BackupScope()
        let bundle = HavenCore.Bundle(
            id: "haven.bundle.kavita",
            name: "Kavita",
            capability: "haven.capability.kavita",
            storage: [
                "content": StoragePolicy(persistent: true, userVisible: true),
            ]
        )
        let result = scope.scope(
            for: makeState(resolvedSettings: ["library_path": "/Users/test/Books"]),
            bundle: bundle
        )

        // Should have the external path + the role-based content dir
        #expect(result.contentPaths.count == 2)
        let paths = Set(result.contentPaths.map(\.path))
        #expect(paths.count == 2) // no duplicates
    }
}
