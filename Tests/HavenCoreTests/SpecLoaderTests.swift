import XCTest
import HavenCore

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
        let music = try XCTUnwrap(registry.capabilitiesByID["haven.capability.music"])
        XCTAssertEqual(music.name, "Music")
        XCTAssertEqual(music.version, "1.0.0")
        XCTAssertEqual(music.summary, "Stream and manage a personal music library.")

        // Bundle
        XCTAssertEqual(registry.bundlesByID.count, 1)
        let bundle = try XCTUnwrap(registry.bundlesByID["haven.bundle.navidrome-single"])
        XCTAssertEqual(bundle.name, "Navidrome (Single)")
        XCTAssertEqual(bundle.capabilityIDs, ["haven.capability.music"])
        XCTAssertEqual(bundle.runtimeUnitIDs, ["haven.unit.navidrome"])
        XCTAssertEqual(bundle.settings.count, 2)

        // RuntimeUnit
        XCTAssertEqual(registry.runtimeUnitsByID.count, 1)
        let unit = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.navidrome"])
        XCTAssertEqual(unit.bundleID, "haven.bundle.navidrome-single")
        XCTAssertEqual(unit.runtimeType, .binary)
        XCTAssertEqual(unit.installSource, "/opt/haven/bin/navidrome")
        XCTAssertNotNil(unit.healthcheck)
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
            dupIssues.contains { $0.source == "haven.capability.music" },
            "Expected duplicate issue for 'haven.capability.music', got: \(dupIssues)"
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
            jsonIssues.contains { $0.source == "broken.json" },
            "Expected issue sourced to 'broken.json', got: \(jsonIssues)"
        )
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
}
