import XCTest
@testable import HavenCore

final class SpecLoaderTests: XCTestCase {

    // MARK: - Helpers

    /// Returns the URL for a named fixture directory inside the test bundle's
    /// copied `Fixtures/` resource folder.
    private func fixtureURL(_ name: String) throws -> URL {
        guard let url = Foundation.Bundle.module
            .url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw XCTSkip("Fixture '\(name)' not found in test bundle.")
        }
        return url
    }

    // MARK: - Successful load

    func testLoadValidSpecs() throws {
        let root = try fixtureURL("ValidSpecs")
        let result = SpecLoader.load(from: root)

        XCTAssertTrue(result.succeeded, "Expected success but got issues: \(result.issues)")
        let registry = try XCTUnwrap(result.registry)

        // Capability
        XCTAssertEqual(registry.capabilitiesByID.count, 1)
        let cap = try XCTUnwrap(registry.capabilitiesByID["haven.capability.test-library"])
        XCTAssertEqual(cap.name, "Test Library")
        XCTAssertEqual(cap.version, "1.0.0")
        XCTAssertEqual(cap.description, "Manage a synthetic test library.")

        // Bundle
        XCTAssertEqual(registry.bundlesByID.count, 1)
        let bundle = try XCTUnwrap(registry.bundlesByID["haven.bundle.test-library-basic"])
        XCTAssertEqual(bundle.name, "Test Library (Basic)")
        XCTAssertEqual(bundle.capability, "haven.capability.test-library")
        XCTAssertEqual(bundle.runtimeUnits, [
            "haven.unit.test-db",
            "haven.unit.test-worker",
            "haven.unit.test-web",
        ])
        XCTAssertEqual(bundle.settings.count, 2)

        // RuntimeUnits
        XCTAssertEqual(registry.runtimeUnitsByID.count, 3)

        let db = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.test-db"])
        XCTAssertEqual(db.bundleID, "haven.bundle.test-library-basic")
        XCTAssertEqual(db.runtimeType, .native)
        // installSource is relative in JSON — SpecLoader resolves it against the service folder.
        let serviceFolder = root.appendingPathComponent("test-library")
        let expectedInstallSource = serviceFolder.appendingPathComponent("Artifacts/HelloService").path
        XCTAssertEqual(db.installSource, expectedInstallSource)
        XCTAssertNotNil(db.healthcheck)

        let worker = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.test-worker"])
        XCTAssertEqual(worker.dependsOn, ["haven.unit.test-db"])

        let web = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.test-web"])
        XCTAssertEqual(web.port, 8080)
        XCTAssertNotNil(web.healthcheck)
    }

    // MARK: - Unknown field rejection

    func testUnknownFieldRejection() throws {
        let root = try fixtureURL("UnknownField")
        let result = SpecLoader.load(from: root)

        XCTAssertFalse(result.succeeded)
        XCTAssertNil(result.registry)

        let unknownFieldIssues = result.issues.filter { $0.kind == .unknownField }
        XCTAssertFalse(unknownFieldIssues.isEmpty, "Expected at least one unknownField issue.")
        XCTAssertTrue(
            unknownFieldIssues.contains { $0.detail.contains("bogusField") },
            "Expected issue mentioning 'bogusField', got: \(unknownFieldIssues)"
        )
    }

    // MARK: - Duplicate ID rejection

    func testDuplicateIDRejection() throws {
        let root = try fixtureURL("DuplicateID")
        let result = SpecLoader.load(from: root)

        XCTAssertFalse(result.succeeded)
        XCTAssertNil(result.registry)

        let dupIssues = result.issues.filter { $0.kind == .duplicateID }
        XCTAssertFalse(dupIssues.isEmpty, "Expected at least one duplicateID issue.")
        XCTAssertTrue(
            dupIssues.contains { $0.source == "haven.capability.test-library" },
            "Expected duplicate issue for 'haven.capability.test-library', got: \(dupIssues)"
        )
    }

    // MARK: - Missing cross-reference rejection

    func testMissingReferenceRejection() throws {
        let root = try fixtureURL("MissingRef")
        let result = SpecLoader.load(from: root)

        XCTAssertFalse(result.succeeded)
        XCTAssertNil(result.registry)

        let refIssues = result.issues.filter { $0.kind == .missingReference }
        XCTAssertGreaterThanOrEqual(refIssues.count, 3,
            "Expected issues for missing capability, runtime unit, and bundle references. Got: \(refIssues)")

        // Bundle → missing capability
        XCTAssertTrue(
            refIssues.contains { $0.detail.contains("haven.capability.nonexistent") },
            "Missing reference to capability not reported: \(refIssues)"
        )
        // Bundle → missing runtime unit
        XCTAssertTrue(
            refIssues.contains { $0.detail.contains("haven.unit.ghost") },
            "Missing reference to runtime unit not reported: \(refIssues)"
        )
        // RuntimeUnit → missing bundle
        XCTAssertTrue(
            refIssues.contains { $0.detail.contains("haven.bundle.nonexistent") },
            "Missing reference to bundle not reported: \(refIssues)"
        )
    }

    // MARK: - Multiple errors collected at once

    func testMultipleErrorsCollected() throws {
        let root = try fixtureURL("MissingRef")
        let result = SpecLoader.load(from: root)

        // MissingRef has a bundle with two bad references and a unit with one bad reference.
        // The loader should collect all of them, not stop at the first.
        XCTAssertGreaterThanOrEqual(result.issues.count, 3,
            "Expected at least 3 issues collected, got \(result.issues.count): \(result.issues)")
    }

    // MARK: - Malformed JSON rejection

    func testMalformedJSONRejection() throws {
        let root = try fixtureURL("MalformedJSON")
        let result = SpecLoader.load(from: root)

        XCTAssertFalse(result.succeeded)
        XCTAssertNil(result.registry)

        let jsonIssues = result.issues.filter { $0.kind == .malformedJSON }
        XCTAssertFalse(jsonIssues.isEmpty, "Expected at least one malformedJSON issue.")
        XCTAssertTrue(
            jsonIssues.contains { $0.source == "broken-service/capability.json" },
            "Expected issue sourced to 'broken-service/capability.json', got: \(jsonIssues)"
        )
    }

    // MARK: - Entrypoint mapping

    func testEntrypointMappingToLaunchArguments() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let serviceDir = tmpDir.appendingPathComponent("ep-test")
        let artifactDir = serviceDir.appendingPathComponent("Artifacts/HelloService")
        try FileManager.default.createDirectory(at: serviceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)

        let capJSON = """
        {
            "id": "haven.capability.ep-test",
            "name": "EP Test",
            "version": "1.0.0",
            "description": "Entrypoint test."
        }
        """.data(using: .utf8)!
        try capJSON.write(to: serviceDir.appendingPathComponent("capability.json"))

        let bundleJSON = """
        {
            "id": "haven.bundle.ep-test",
            "name": "EP Bundle",
            "capability": "haven.capability.ep-test",
            "runtimeUnits": ["haven.unit.ep-test"],
            "version": "2.0.0"
        }
        """.data(using: .utf8)!
        try bundleJSON.write(to: serviceDir.appendingPathComponent("bundle.json"))

        let unitJSON = """
        [{
            "id": "haven.unit.ep-test",
            "bundleID": "haven.bundle.ep-test",
            "runtimeType": "native",
            "installSource": "Artifacts/HelloService",
            "entrypoint": {
                "command": "/usr/local/bin/hello",
                "args": ["hello", "--port", "8080"],
                "env": {"PORT": "8080"}
            },
            "version": "2.0.0"
        }]
        """.data(using: .utf8)!
        try unitJSON.write(to: serviceDir.appendingPathComponent("runtimes.json"))

        let result = SpecLoader.load(from: tmpDir)
        XCTAssertTrue(result.succeeded, "Expected success but got issues: \(result.issues)")
        let registry = try XCTUnwrap(result.registry)

        // Capability
        let cap = try XCTUnwrap(registry.capabilitiesByID["haven.capability.ep-test"])
        XCTAssertEqual(cap.description, "Entrypoint test.")

        // Bundle
        let bundle = try XCTUnwrap(registry.bundlesByID["haven.bundle.ep-test"])
        XCTAssertEqual(bundle.capability, "haven.capability.ep-test")
        XCTAssertEqual(bundle.runtimeUnits, ["haven.unit.ep-test"])
        XCTAssertEqual(bundle.version, "2.0.0")

        // RuntimeUnit: entrypoint.args → launchArguments, entrypoint.env → environment
        let unit = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.ep-test"])
        XCTAssertEqual(unit.launchArguments, ["hello", "--port", "8080"])
        XCTAssertEqual(unit.environment, ["PORT": "8080"])
        XCTAssertEqual(unit.version, "2.0.0")
    }

    // MARK: - Entrypoint takes precedence over top-level fields

    func testEntrypointPrecedenceOverTopLevel() throws {
        let json = """
        {
            "id": "haven.unit.ep-test",
            "bundleID": "haven.bundle.test",
            "runtimeType": "native",
            "installSource": "Artifacts/Test",
            "launchArguments": ["should-be-overridden"],
            "environment": {"OLD": "overridden"},
            "entrypoint": {
                "command": "ignored",
                "args": ["new-arg", "--flag"],
                "env": {"NEW": "value"}
            }
        }
        """.data(using: .utf8)!

        let (unit, issues) = StrictJSONDecoder.decode(
            RuntimeUnit.self,
            from: json,
            knownKeys: StrictJSONDecoder.runtimeUnitKeys,
            source: "ep-test.json"
        )
        XCTAssertTrue(issues.isEmpty, "Unexpected issues: \(issues)")
        let u = try XCTUnwrap(unit)
        XCTAssertEqual(u.launchArguments, ["new-arg", "--flag"])
        XCTAssertEqual(u.environment, ["NEW": "value"])
    }

    // MARK: - Version field accepted on Bundle and RuntimeUnit

    func testVersionFieldAcceptedOnAllSpecs() throws {
        // Capability already has version as a required field — verify no unknown-field error.
        let capJSON = """
        {"id": "test.cap", "name": "Test", "version": "1.0.0"}
        """.data(using: .utf8)!
        let (_, capIssues) = StrictJSONDecoder.decode(
            Capability.self, from: capJSON,
            knownKeys: StrictJSONDecoder.capabilityKeys, source: "cap.json"
        )
        XCTAssertTrue(capIssues.isEmpty, "Unexpected capability issues: \(capIssues)")

        // Bundle with version
        let bundleJSON = """
        {"id": "test.bundle", "name": "Test", "capability": "test.cap", "version": "2.0.0"}
        """.data(using: .utf8)!
        let (bundle, bundleIssues) = StrictJSONDecoder.decode(
            Bundle.self, from: bundleJSON,
            knownKeys: StrictJSONDecoder.bundleKeys, source: "bundle.json"
        )
        XCTAssertTrue(bundleIssues.isEmpty, "Unexpected bundle issues: \(bundleIssues)")
        XCTAssertEqual(try XCTUnwrap(bundle).version, "2.0.0")

        // RuntimeUnit with version
        let unitJSON = """
        {
            "id": "test.unit", "bundleID": "test.bundle",
            "runtimeType": "native", "installSource": "bin/test",
            "launchArguments": ["test"], "version": "3.0.0"
        }
        """.data(using: .utf8)!
        let (unit, unitIssues) = StrictJSONDecoder.decode(
            RuntimeUnit.self, from: unitJSON,
            knownKeys: StrictJSONDecoder.runtimeUnitKeys, source: "unit.json"
        )
        XCTAssertTrue(unitIssues.isEmpty, "Unexpected unit issues: \(unitIssues)")
        XCTAssertEqual(try XCTUnwrap(unit).version, "3.0.0")
    }

    // MARK: - Truly unknown fields still rejected

    func testTrulyUnknownFieldsStillRejected() throws {
        let json = """
        {"id": "test.cap", "name": "Test", "version": "1.0.0", "bogusField": "bad"}
        """.data(using: .utf8)!
        let (_, issues) = StrictJSONDecoder.decode(
            Capability.self, from: json,
            knownKeys: StrictJSONDecoder.capabilityKeys, source: "bad.json"
        )
        XCTAssertTrue(issues.contains { $0.kind == .unknownField && $0.detail.contains("bogusField") })
    }

    // MARK: - Empty directory is a valid (empty) load

    func testEmptyDirectoryProducesEmptyRegistry() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let result = SpecLoader.load(from: tmpDir)
        XCTAssertTrue(result.succeeded)
        let registry = try XCTUnwrap(result.registry)
        XCTAssertTrue(registry.capabilitiesByID.isEmpty)
        XCTAssertTrue(registry.bundlesByID.isEmpty)
        XCTAssertTrue(registry.runtimeUnitsByID.isEmpty)
    }

    // MARK: - installSource path resolution

    /// Helper: creates a minimal valid spec set in a temp directory using per-service layout.
    private func makeSpecsDir(
        installSource: String,
        createArtifact: Bool = true,
        artifactRelativePath: String? = nil
    ) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let serviceDir = tmpDir.appendingPathComponent("test-service")
        try FileManager.default.createDirectory(at: serviceDir, withIntermediateDirectories: true)

        if createArtifact {
            let artifactPath = artifactRelativePath ?? installSource
            let artifactDir = serviceDir.appendingPathComponent(artifactPath)
            try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)
        }

        let capJSON = """
        {"id": "test.cap", "name": "Test", "version": "1.0.0"}
        """.data(using: .utf8)!
        try capJSON.write(to: serviceDir.appendingPathComponent("capability.json"))

        let bundleJSON = """
        {"id": "test.bundle", "name": "Test", "capability": "test.cap", "runtimeUnits": ["test.unit"]}
        """.data(using: .utf8)!
        try bundleJSON.write(to: serviceDir.appendingPathComponent("bundle.json"))

        let unitJSON = """
        [{
            "id": "test.unit",
            "bundleID": "test.bundle",
            "runtimeType": "native",
            "installSource": "\(installSource)",
            "launchArguments": ["test"]
        }]
        """.data(using: .utf8)!
        try unitJSON.write(to: serviceDir.appendingPathComponent("runtimes.json"))

        return tmpDir
    }

    func testRelativeInstallSourceResolution() throws {
        let root = try makeSpecsDir(installSource: "Artifacts/MyService")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "Expected success but got issues: \(result.issues)")
        let registry = try XCTUnwrap(result.registry)

        let unit = try XCTUnwrap(registry.runtimeUnitsByID["test.unit"])
        XCTAssertTrue(unit.installSource.hasPrefix("/"), "Resolved path must be absolute.")
        XCTAssertTrue(unit.installSource.hasSuffix("test-service/Artifacts/MyService"),
                      "Relative path should be resolved under service folder.")
    }

    func testAbsoluteInstallSourceUnchanged() throws {
        // Use /usr/bin which exists on every Mac.
        let root = try makeSpecsDir(installSource: "/usr/bin", createArtifact: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "Expected success but got issues: \(result.issues)")
        let registry = try XCTUnwrap(result.registry)

        let unit = try XCTUnwrap(registry.runtimeUnitsByID["test.unit"])
        XCTAssertEqual(unit.installSource, "/usr/bin", "Absolute path must not be modified.")
    }

    func testRelativePathWithSpaces() throws {
        let root = try makeSpecsDir(installSource: "My Artifacts/Hello Service")
        defer { try? FileManager.default.removeItem(at: root) }

        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "Expected success but got issues: \(result.issues)")
        let registry = try XCTUnwrap(result.registry)

        let unit = try XCTUnwrap(registry.runtimeUnitsByID["test.unit"])
        XCTAssertTrue(unit.installSource.hasPrefix("/"), "Resolved path must be absolute.")
        XCTAssertTrue(unit.installSource.hasSuffix("test-service/My Artifacts/Hello Service"),
                      "Path with spaces should resolve correctly.")
    }

    func testMissingRelativePathProducesWarning() throws {
        let root = try makeSpecsDir(installSource: "Nonexistent/Missing", createArtifact: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = SpecLoader.load(from: root)
        // Missing installSource is a warning, not a fatal error — catalog still loads.
        XCTAssertTrue(result.succeeded, "Expected success (with warnings) but got errors: \(result.issues)")
        XCTAssertNotNil(result.registry)

        let warnings = result.warnings
        XCTAssertFalse(warnings.isEmpty, "Expected at least one warning.")
        XCTAssertTrue(
            warnings.contains { $0.source == "test.unit" && $0.detail.contains("Nonexistent/Missing") },
            "Expected warning mentioning the missing path, got: \(warnings)"
        )
    }

    // MARK: - Artifact field support

    func testArtifactFieldDecodesWithoutUnknownKeyWarning() throws {
        let json = """
        {
            "id": "test.unit",
            "bundleID": "test.bundle",
            "runtimeType": "native",
            "launchArguments": ["test"],
            "installSource": "/opt/bin/test",
            "artifact": {
                "type": "github-release",
                "repo": "owner/repo",
                "version": "v1.0.0",
                "assets": [
                    {"os": "macos", "arch": "arm64", "file": "app-arm64.zip"}
                ],
                "archive": {"format": "zip", "stripFirstDirectory": true}
            }
        }
        """.data(using: .utf8)!

        let (unit, issues) = StrictJSONDecoder.decode(
            RuntimeUnit.self, from: json,
            knownKeys: StrictJSONDecoder.runtimeUnitKeys, source: "unit.json"
        )

        XCTAssertTrue(issues.isEmpty, "Unexpected issues: \(issues)")
        let u = try XCTUnwrap(unit)
        XCTAssertNotNil(u.artifact)
        XCTAssertEqual(u.artifact?.type, .githubRelease)
        XCTAssertEqual(u.artifact?.repo, "owner/repo")
        XCTAssertEqual(u.artifact?.version, "v1.0.0")
        XCTAssertEqual(u.artifact?.assets.count, 1)
        XCTAssertEqual(u.artifact?.assets.first?.os, "macos")
        XCTAssertEqual(u.artifact?.assets.first?.arch, "arm64")
        XCTAssertEqual(u.artifact?.assets.first?.file, "app-arm64.zip")
        XCTAssertEqual(u.artifact?.archive?.format, "zip")
        XCTAssertEqual(u.artifact?.archive?.stripFirstDirectory, true)
    }

    func testArtifactFieldOptionalInstallSource() throws {
        // When artifact is present, installSource can be omitted
        let json = """
        {
            "id": "test.unit",
            "bundleID": "test.bundle",
            "runtimeType": "native",
            "entrypoint": {"args": ["--port", "8080"]},
            "artifact": {
                "type": "github-release",
                "repo": "owner/repo",
                "version": "v1.0.0",
                "assets": [
                    {"os": "macos", "arch": "arm64", "file": "app.zip"}
                ]
            }
        }
        """.data(using: .utf8)!

        let (unit, issues) = StrictJSONDecoder.decode(
            RuntimeUnit.self, from: json,
            knownKeys: StrictJSONDecoder.runtimeUnitKeys, source: "unit.json"
        )

        XCTAssertTrue(issues.isEmpty, "Unexpected issues: \(issues)")
        let u = try XCTUnwrap(unit)
        XCTAssertEqual(u.installSource, "")
        XCTAssertNotNil(u.artifact)
        XCTAssertEqual(u.launchArguments, ["--port", "8080"])

        // Validation should pass because artifact is present
        XCTAssertNoThrow(try u.validate())
    }

    func testValidationFailsWithEmptyInstallSourceAndNoArtifact() throws {
        let unit = RuntimeUnit(
            id: "test.unit",
            bundleID: "test.bundle",
            runtimeType: .native,
            installSource: "",
            launchArguments: ["test"]
        )

        XCTAssertThrowsError(try unit.validate()) { error in
            let validationError = error as? ValidationError
            XCTAssertNotNil(validationError)
            XCTAssertTrue(validationError?.message.contains("installSource") == true)
        }
    }

    func testValidationPassesWithEmptyLaunchArgsAndArtifact() throws {
        let artifact = Artifact(
            type: .githubRelease,
            repo: "owner/repo",
            version: "v1.0.0",
            assets: [ArtifactAsset(os: "macos", arch: "arm64", file: "app.zip")]
        )
        let unit = RuntimeUnit(
            id: "test.unit",
            bundleID: "test.bundle",
            runtimeType: .native,
            installSource: "",
            launchArguments: [],
            artifact: artifact
        )

        XCTAssertNoThrow(try unit.validate())
    }

    func testNestedUnknownFieldsDetected() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let serviceDir = tmpDir.appendingPathComponent("nested-check")
        try FileManager.default.createDirectory(at: serviceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let capJSON = """
        {"id": "test.cap", "name": "Test", "version": "1.0.0"}
        """.data(using: .utf8)!
        try capJSON.write(to: serviceDir.appendingPathComponent("capability.json"))

        let bundleJSON = """
        {"id": "test.bundle", "name": "Test", "capability": "test.cap", "runtimeUnits": ["test.unit"]}
        """.data(using: .utf8)!
        try bundleJSON.write(to: serviceDir.appendingPathComponent("bundle.json"))

        // runtimes.json with unknown fields at multiple nesting levels
        let unitJSON = """
        [{
            "id": "test.unit",
            "bundleID": "test.bundle",
            "runtimeType": "python",
            "python": {
                "package": "pkg", "version": "1.0",
                "entrypoint": { "module": "mod", "bogusEntryField": true },
                "bogusConfigField": "bad"
            },
            "healthcheck": {
                "type": "http", "target": "http://localhost:8080/",
                "intervalSeconds": 10, "retries": 3,
                "bogusHCField": 42
            }
        }]
        """.data(using: .utf8)!
        try unitJSON.write(to: serviceDir.appendingPathComponent("runtimes.json"))

        let result = SpecLoader.load(from: tmpDir)
        let unknowns = result.issues.filter { $0.kind == .unknownField }

        XCTAssertTrue(
            unknowns.contains { $0.detail.contains("bogusConfigField") },
            "Expected warning for python.bogusConfigField, got: \(unknowns)"
        )
        XCTAssertTrue(
            unknowns.contains { $0.detail.contains("bogusEntryField") },
            "Expected warning for python.entrypoint.bogusEntryField, got: \(unknowns)"
        )
        XCTAssertTrue(
            unknowns.contains { $0.detail.contains("bogusHCField") },
            "Expected warning for healthcheck.bogusHCField, got: \(unknowns)"
        )
    }

    func testArtifactFieldInRuntimesJsonArray() throws {
        // Test that the SpecLoader can load a runtimes.json with artifact fields
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let serviceDir = tmpDir.appendingPathComponent("artifact-service")
        try FileManager.default.createDirectory(at: serviceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let capJSON = """
        {"id": "test.cap", "name": "Test", "version": "1.0.0"}
        """.data(using: .utf8)!
        try capJSON.write(to: serviceDir.appendingPathComponent("capability.json"))

        let bundleJSON = """
        {"id": "test.bundle", "name": "Test", "capability": "test.cap", "runtimeUnits": ["test.unit"]}
        """.data(using: .utf8)!
        try bundleJSON.write(to: serviceDir.appendingPathComponent("bundle.json"))

        let unitJSON = """
        [{
            "id": "test.unit",
            "bundleID": "test.bundle",
            "runtimeType": "native",
            "entrypoint": {"args": ["--port", "8080"]},
            "artifact": {
                "type": "github-release",
                "repo": "owner/hello-service",
                "version": "v1.0.0",
                "assets": [
                    {"os": "macos", "arch": "arm64", "file": "hello-arm64.zip"},
                    {"os": "macos", "arch": "x86_64", "file": "hello-x86.zip"}
                ],
                "archive": {"format": "zip"}
            }
        }]
        """.data(using: .utf8)!
        try unitJSON.write(to: serviceDir.appendingPathComponent("runtimes.json"))

        let result = SpecLoader.load(from: tmpDir)

        // Should succeed — no errors, no unknown-key warnings for "artifact"
        XCTAssertTrue(result.succeeded, "Expected success but got issues: \(result.issues)")
        let registry = try XCTUnwrap(result.registry)

        let unit = try XCTUnwrap(registry.runtimeUnitsByID["test.unit"])
        XCTAssertNotNil(unit.artifact)
        XCTAssertEqual(unit.artifact?.repo, "owner/hello-service")
        XCTAssertEqual(unit.artifact?.assets.count, 2)
    }
}
