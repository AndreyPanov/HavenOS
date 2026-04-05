import XCTest
@testable import HavenCore

/// Tests that validate the local catalog loading flow used by the app.
///
/// These exercise `SpecLoader` with directory structures matching the
/// `~/.haven/Catalog/` layout that `ServiceManager` expects.
final class CatalogLoadingTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogLoadingTests-\(UUID().uuidString)")
    }

    /// Creates a minimal valid catalog folder with one service subfolder.
    private func makeValidCatalogFolder() throws -> URL {
        let root = makeTempDir()
        let fm = FileManager.default

        let serviceDir = root.appendingPathComponent("hello-service")
        let artifactDir = serviceDir.appendingPathComponent("Artifacts/HelloService")
        try fm.createDirectory(at: serviceDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: artifactDir, withIntermediateDirectories: true)

        try """
        {
            "id": "haven.capability.hello-service",
            "name": "Hello Service",
            "version": "1.0.0",
            "description": "A greeting service."
        }
        """.data(using: .utf8)!.write(to: serviceDir.appendingPathComponent("capability.json"))

        try """
        {
            "id": "haven.bundle.hello-service-basic",
            "name": "Hello Service (Basic)",
            "capability": "haven.capability.hello-service",
            "runtimeUnits": ["haven.unit.hello-service"]
        }
        """.data(using: .utf8)!.write(to: serviceDir.appendingPathComponent("bundle.json"))

        try """
        [{
            "id": "haven.unit.hello-service",
            "bundleID": "haven.bundle.hello-service-basic",
            "runtimeType": "native",
            "installSource": "Artifacts/HelloService",
            "launchArguments": ["serve", "--port", "8080"],
            "port": 8080
        }]
        """.data(using: .utf8)!.write(to: serviceDir.appendingPathComponent("runtimes.json"))

        return root
    }

    // MARK: - Valid catalog folder

    func testLoadValidCatalogFolder() throws {
        let root = try makeValidCatalogFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "Expected success but got issues: \(result.issues)")

        let registry = try XCTUnwrap(result.registry)
        XCTAssertEqual(registry.capabilitiesByID.count, 1)
        XCTAssertEqual(registry.bundlesByID.count, 1)
        XCTAssertEqual(registry.runtimeUnitsByID.count, 1)

        let cap = try XCTUnwrap(registry.capabilitiesByID["haven.capability.hello-service"])
        XCTAssertEqual(cap.name, "Hello Service")

        let bundle = try XCTUnwrap(registry.bundlesByID["haven.bundle.hello-service-basic"])
        XCTAssertEqual(bundle.capability, "haven.capability.hello-service")

        let unit = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.hello-service"])
        XCTAssertTrue(unit.installSource.hasPrefix("/"), "installSource should be resolved to absolute")
        XCTAssertTrue(unit.installSource.hasSuffix("hello-service/Artifacts/HelloService"))
        XCTAssertEqual(unit.port, 8080)
    }

    // MARK: - Missing catalog folder

    func testMissingCatalogFolder() throws {
        let nonexistent = makeTempDir().appendingPathComponent("does-not-exist")
        let exists = FileManager.default.fileExists(atPath: nonexistent.path)
        XCTAssertFalse(exists, "Path should not exist for this test")

        // The app checks fileExists before calling SpecLoader.
        // SpecLoader itself handles missing directories gracefully.
        let result = SpecLoader.load(from: nonexistent)
        XCTAssertTrue(result.succeeded, "Empty/missing dirs produce an empty but valid registry")
        let registry = try XCTUnwrap(result.registry)
        XCTAssertTrue(registry.capabilitiesByID.isEmpty)
    }

    // MARK: - Invalid specs show issues

    func testInvalidSpecsShowIssues() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let serviceDir = root.appendingPathComponent("bad-service")
        try FileManager.default.createDirectory(at: serviceDir, withIntermediateDirectories: true)

        // Write malformed JSON
        try "{ not valid json }".data(using: .utf8)!
            .write(to: serviceDir.appendingPathComponent("capability.json"))

        let result = SpecLoader.load(from: root)
        XCTAssertFalse(result.succeeded)
        XCTAssertNil(result.registry)

        let jsonIssues = result.issues.filter { $0.kind == .malformedJSON }
        XCTAssertFalse(jsonIssues.isEmpty, "Expected malformedJSON issue")
    }

    // MARK: - Empty catalog folder

    func testEmptyCatalogFolder() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded)

        let registry = try XCTUnwrap(result.registry)
        XCTAssertTrue(registry.capabilitiesByID.isEmpty)
        XCTAssertTrue(registry.bundlesByID.isEmpty)
        XCTAssertTrue(registry.runtimeUnitsByID.isEmpty)
    }

    // MARK: - Switching catalog folders

    func testSwitchingCatalogFolders() throws {
        let root1 = try makeValidCatalogFolder()
        defer { try? FileManager.default.removeItem(at: root1) }

        let root2 = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root2) }

        let serviceDir2 = root2.appendingPathComponent("other-service")
        let artifactDir2 = serviceDir2.appendingPathComponent("Artifacts/OtherService")
        try FileManager.default.createDirectory(at: serviceDir2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artifactDir2, withIntermediateDirectories: true)

        try """
        {
            "id": "haven.capability.other-service",
            "name": "Other Service",
            "version": "2.0.0",
            "description": "A different service."
        }
        """.data(using: .utf8)!.write(to: serviceDir2.appendingPathComponent("capability.json"))

        try """
        {
            "id": "haven.bundle.other-service-basic",
            "name": "Other Service (Basic)",
            "capability": "haven.capability.other-service",
            "runtimeUnits": ["haven.unit.other-service"]
        }
        """.data(using: .utf8)!.write(to: serviceDir2.appendingPathComponent("bundle.json"))

        try """
        [{
            "id": "haven.unit.other-service",
            "bundleID": "haven.bundle.other-service-basic",
            "runtimeType": "native",
            "installSource": "Artifacts/OtherService",
            "launchArguments": ["run"]
        }]
        """.data(using: .utf8)!.write(to: serviceDir2.appendingPathComponent("runtimes.json"))

        // Load from folder 1
        let result1 = SpecLoader.load(from: root1)
        XCTAssertTrue(result1.succeeded)
        let reg1 = try XCTUnwrap(result1.registry)
        XCTAssertNotNil(reg1.capabilitiesByID["haven.capability.hello-service"])
        XCTAssertNil(reg1.capabilitiesByID["haven.capability.other-service"])

        // Load from folder 2
        let result2 = SpecLoader.load(from: root2)
        XCTAssertTrue(result2.succeeded)
        let reg2 = try XCTUnwrap(result2.registry)
        XCTAssertNil(reg2.capabilitiesByID["haven.capability.hello-service"])
        XCTAssertNotNil(reg2.capabilitiesByID["haven.capability.other-service"])
    }

    // MARK: - Multiple services in one catalog

    func testMultipleServicesInCatalog() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default

        for (i, name) in ["svc-one", "svc-two"].enumerated() {
            let serviceDir = root.appendingPathComponent(name)
            let artifactDir = serviceDir.appendingPathComponent("Artifacts/Svc\(i + 1)")
            try fm.createDirectory(at: serviceDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: artifactDir, withIntermediateDirectories: true)

            try """
            {"id": "haven.capability.\(name)", "name": "\(name)", "version": "1.0.0"}
            """.data(using: .utf8)!.write(to: serviceDir.appendingPathComponent("capability.json"))

            try """
            {
                "id": "haven.bundle.\(name)",
                "name": "\(name) bundle",
                "capability": "haven.capability.\(name)",
                "runtimeUnits": ["haven.unit.\(name)"]
            }
            """.data(using: .utf8)!.write(to: serviceDir.appendingPathComponent("bundle.json"))

            try """
            [{
                "id": "haven.unit.\(name)",
                "bundleID": "haven.bundle.\(name)",
                "runtimeType": "native",
                "installSource": "Artifacts/Svc\(i + 1)",
                "launchArguments": ["run"]
            }]
            """.data(using: .utf8)!.write(to: serviceDir.appendingPathComponent("runtimes.json"))
        }

        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "Issues: \(result.issues)")

        let registry = try XCTUnwrap(result.registry)
        XCTAssertEqual(registry.capabilitiesByID.count, 2)
        XCTAssertEqual(registry.bundlesByID.count, 2)
        XCTAssertEqual(registry.runtimeUnitsByID.count, 2)
    }

    // MARK: - Auto-creation of catalog folder

    func testAutoCreateCatalogFolder() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: root.path), "Folder should not exist yet")

        // Simulate what ServiceManager.ensureCatalogFolderExists now does
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        // Verify the folder was created
        XCTAssertTrue(fm.fileExists(atPath: root.path))

        // Loading from the now-existing empty folder should succeed
        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded)
        let registry = try XCTUnwrap(result.registry)
        XCTAssertTrue(registry.capabilitiesByID.isEmpty)
    }

    // MARK: - Auto-created folder then populated loads correctly

    func testAutoCreatedFolderThenPopulated() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        // Auto-create root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Initially empty
        let emptyResult = SpecLoader.load(from: root)
        XCTAssertTrue(emptyResult.succeeded)
        XCTAssertEqual(try XCTUnwrap(emptyResult.registry).capabilitiesByID.count, 0)

        // Add a service
        let serviceDir = root.appendingPathComponent("test-svc")
        let artifactDir = serviceDir.appendingPathComponent("Artifacts/TestSvc")
        try FileManager.default.createDirectory(at: serviceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

        try """
        {"id": "test.cap", "name": "Test", "version": "1.0.0"}
        """.data(using: .utf8)!.write(to: serviceDir.appendingPathComponent("capability.json"))

        try """
        {"id": "test.bundle", "name": "Test", "capability": "test.cap", "runtimeUnits": ["test.unit"]}
        """.data(using: .utf8)!.write(to: serviceDir.appendingPathComponent("bundle.json"))

        try """
        [{"id": "test.unit", "bundleID": "test.bundle", "runtimeType": "native", "installSource": "Artifacts/TestSvc", "launchArguments": ["run"]}]
        """.data(using: .utf8)!.write(to: serviceDir.appendingPathComponent("runtimes.json"))

        // Reload should now find the spec
        let populatedResult = SpecLoader.load(from: root)
        XCTAssertTrue(populatedResult.succeeded, "Issues: \(populatedResult.issues)")
        let registry = try XCTUnwrap(populatedResult.registry)
        XCTAssertEqual(registry.capabilitiesByID.count, 1)
        XCTAssertEqual(registry.bundlesByID.count, 1)
        XCTAssertEqual(registry.runtimeUnitsByID.count, 1)
    }

    // MARK: - Catalog counts from loaded registry

    func testCatalogCountsFromLoadedRegistry() throws {
        let root = try makeValidCatalogFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded)
        let registry = try XCTUnwrap(result.registry)

        // Verify the counts that CatalogCounts would carry
        XCTAssertEqual(registry.capabilitiesByID.count, 1)
        XCTAssertEqual(registry.bundlesByID.count, 1)
        XCTAssertEqual(registry.runtimeUnitsByID.count, 1)
    }

    // MARK: - Partially invalid folder still reports all issues

    func testPartiallyInvalidFolderReportsAllIssues() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default

        // One valid service folder
        let goodDir = root.appendingPathComponent("good-service")
        try fm.createDirectory(at: goodDir, withIntermediateDirectories: true)
        try """
        {"id": "test.cap", "name": "Test", "version": "1.0.0"}
        """.data(using: .utf8)!.write(to: goodDir.appendingPathComponent("capability.json"))

        // One service folder with malformed JSON
        let badDir = root.appendingPathComponent("bad-service")
        try fm.createDirectory(at: badDir, withIntermediateDirectories: true)
        try "{ broken json }".data(using: .utf8)!
            .write(to: badDir.appendingPathComponent("capability.json"))

        let result = SpecLoader.load(from: root)
        XCTAssertFalse(result.succeeded, "Should fail due to malformed JSON")
        XCTAssertNil(result.registry)

        let jsonIssues = result.issues.filter { $0.kind == .malformedJSON }
        XCTAssertEqual(jsonIssues.count, 1)
        XCTAssertEqual(jsonIssues.first?.source, "bad-service/capability.json")
    }

    // MARK: - Install uses loaded capability ID

    func testRegistryContainsCapabilityIDForInstall() throws {
        let root = try makeValidCatalogFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded)
        let registry = try XCTUnwrap(result.registry)

        // The capability ID that Discovery would pass to installService
        let capabilityID = "haven.capability.hello-service"
        XCTAssertNotNil(registry.capabilitiesByID[capabilityID],
                        "Registry should contain the capability ID used by Install action")

        // Verify the bundle and units are also resolvable
        let cap = try XCTUnwrap(registry.capabilitiesByID[capabilityID])
        let matchingBundles = registry.bundlesByID.values.filter { $0.capability == cap.id }
        XCTAssertFalse(matchingBundles.isEmpty, "At least one bundle should implement this capability")

        let bundle = try XCTUnwrap(matchingBundles.first)
        for unitID in bundle.runtimeUnits {
            XCTAssertNotNil(registry.runtimeUnitsByID[unitID],
                            "Runtime unit \(unitID) referenced by bundle should be in registry")
        }
    }
}
