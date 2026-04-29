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

    // MARK: - Unified content_paths Key

    @Test("Single path from content_paths is included")
    func singleContentPath() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            resolvedSettings: ["content_paths": "/Users/test/Books"]
        ))

        #expect(result.contentPaths.count == 1)
        #expect(result.contentPaths[0].path == "/Users/test/Books")
    }

    @Test("Multiple semicolon-separated content_paths are all included")
    func multipleContentPaths() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            resolvedSettings: ["content_paths": "/Users/test/Books;/Users/test/Comics"]
        ))

        let paths = result.contentPaths.map(\.path)
        #expect(paths.count == 2)
        #expect(paths.contains("/Users/test/Books"))
        #expect(paths.contains("/Users/test/Comics"))
    }

    @Test("Duplicate paths in content_paths are deduplicated")
    func contentPathsDeduplication() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            resolvedSettings: ["content_paths": "/Users/test/Books;/Users/test/Books"]
        ))

        #expect(result.contentPaths.count == 1)
    }

    @Test("Empty semicolon segments in content_paths are ignored")
    func emptySegmentsIgnored() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            resolvedSettings: ["content_paths": "/Users/test/Books;;/Users/test/Comics;"]
        ))

        #expect(result.contentPaths.count == 2)
    }

    @Test("Tilde in content_paths is expanded")
    func tildeExpansion() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            resolvedSettings: ["content_paths": "~/Books;~/Comics"]
        ))

        for path in result.contentPaths {
            #expect(!path.path.contains("~"))
        }
        #expect(result.contentPaths.count == 2)
    }

    @Test("content_paths works identically for any capability")
    func unifiedAcrossCapabilities() {
        let scope = BackupScope()

        let books = scope.scope(for: makeState(
            capability: "haven.capability.kavita",
            resolvedSettings: ["content_paths": "/a;/b"]
        ))
        let movies = scope.scope(for: makeState(
            capability: "haven.capability.jellyfin",
            resolvedSettings: ["content_paths": "/c;/d"]
        ))
        let music = scope.scope(for: makeState(
            capability: "haven.capability.navidrome",
            resolvedSettings: ["content_paths": "/e"]
        ))

        #expect(books.contentPaths.count == 2)
        #expect(movies.contentPaths.count == 2)
        #expect(music.contentPaths.count == 1)
    }

    // MARK: - Legacy Fallback (pre-unification services)

    @Test("Legacy library_path fallback works when content_paths absent")
    func legacyLibraryPath() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            resolvedSettings: ["library_path": "/Users/test/Books"]
        ))

        #expect(result.contentPaths.count == 1)
        #expect(result.contentPaths[0].path == "/Users/test/Books")
    }

    @Test("Legacy music_path fallback works when content_paths absent")
    func legacyMusicPath() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            capability: "haven.capability.navidrome",
            resolvedSettings: ["music_path": "/Users/test/Music"]
        ))

        #expect(result.contentPaths.count == 1)
        #expect(result.contentPaths[0].path == "/Users/test/Music")
    }

    @Test("Legacy movies_path fallback works when content_paths absent")
    func legacyMoviesPath() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            capability: "haven.capability.jellyfin",
            resolvedSettings: ["movies_path": "/Users/test/Movies"]
        ))

        #expect(result.contentPaths.count == 1)
        #expect(result.contentPaths[0].path == "/Users/test/Movies")
    }

    @Test("Legacy library_paths multi-path fallback works when content_paths absent")
    func legacyLibraryPaths() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            resolvedSettings: [
                "library_path": "/Users/test/Books",
                "library_paths": "/Users/test/Books;/Users/test/Comics"
            ]
        ))

        let paths = result.contentPaths.map(\.path)
        #expect(paths.contains("/Users/test/Books"))
        #expect(paths.contains("/Users/test/Comics"))
        #expect(result.contentPaths.count == 2) // deduplicated
    }

    @Test("Legacy movies_paths multi-path fallback works when content_paths absent")
    func legacyMoviesPaths() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            capability: "haven.capability.jellyfin",
            resolvedSettings: [
                "movies_path": "/Users/test/Movies",
                "movies_paths": "/Users/test/Movies;/Users/test/TV Shows"
            ]
        ))

        let paths = result.contentPaths.map(\.path)
        #expect(paths.contains("/Users/test/Movies"))
        #expect(paths.contains("/Users/test/TV Shows"))
        #expect(result.contentPaths.count == 2)
    }

    @Test("content_paths takes precedence over legacy keys")
    func unifiedOverridesLegacy() {
        let scope = BackupScope()
        let result = scope.scope(for: makeState(
            resolvedSettings: [
                "content_paths": "/Users/test/Comics",
                "library_path": "/Users/test/Books",
            ]
        ))

        // content_paths wins, library_path ignored
        #expect(result.contentPaths.count == 1)
        #expect(result.contentPaths[0].path == "/Users/test/Comics")
    }

    // MARK: - Storage Policy

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

    @Test("No duplicate paths when content_paths and policy both resolve to same dir")
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
            for: makeState(resolvedSettings: ["content_paths": "/Users/test/Books"]),
            bundle: bundle
        )

        // Should have the external path + the role-based content dir
        #expect(result.contentPaths.count == 2)
        let paths = Set(result.contentPaths.map(\.path))
        #expect(paths.count == 2) // no duplicates
    }

    // MARK: - scopeAll

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
}
