import XCTest
import Foundation
import HavenCore
@testable import HavenInstaller

final class DependencyValidatorTests: XCTestCase {

    // MARK: - Helpers

    /// Create a validator with a mock command runner and a temp directory
    /// containing specific "binaries".
    private func makeValidator(
        binaries: [String] = [],
        commandResults: [String: Bool] = [:]
    ) -> (DependencyValidator, URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-dep-test-\(UUID().uuidString)")
        let binDir = tmpDir.appendingPathComponent("bin")
        try? FileManager.default.createDirectory(
            at: binDir, withIntermediateDirectories: true
        )

        // Create fake executables
        for name in binaries {
            let path = binDir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: path.path, contents: nil)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: path.path
            )
        }

        let validator = DependencyValidator(
            commandRunner: { command in
                commandResults[command] ?? false
            }
        )

        return (validator, tmpDir)
    }

    // MARK: - Real Binary Discovery

    func testFindsRealBinaryInKnownPaths() {
        // /usr/bin/uname should exist on all macOS systems
        let validator = DependencyValidator(
            commandRunner: { _ in true }
        )

        let dep = Dependency(
            id: "uname",
            kind: .helperBinary,
            required: true
        )

        let results = validator.validate(dependencies: [dep])
        XCTAssertEqual(results.count, 1)

        if case .found(let path) = results[0].status {
            XCTAssertTrue(path.hasSuffix("/uname"))
        } else {
            XCTFail("Expected uname to be found")
        }
    }

    func testMissingBinaryReportsCorrectStatus() {
        let validator = DependencyValidator(
            commandRunner: { _ in false }
        )

        let dep = Dependency(
            id: "nonexistent_binary_xyz_123",
            kind: .helperBinary,
            required: true
        )

        let results = validator.validate(dependencies: [dep])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].status, .missing)
        XCTAssertTrue(results[0].isBlocker)
    }

    func testOptionalMissingIsWarningNotBlocker() {
        let validator = DependencyValidator(
            commandRunner: { _ in false }
        )

        let dep = Dependency(
            id: "nonexistent_optional_xyz",
            kind: .helperBinary,
            required: false
        )

        let results = validator.validate(dependencies: [dep])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].status, .missing)
        XCTAssertTrue(results[0].isWarning)
        XCTAssertFalse(results[0].isBlocker)
    }

    // MARK: - ValidateCommand

    func testValidateCommandWithAbsolutePath() {
        let validator = DependencyValidator(
            commandRunner: { command in
                command == "/opt/homebrew/bin/ffmpeg -version"
            }
        )

        let dep = Dependency(
            id: "ffmpeg_test_fake",
            kind: .helperBinary,
            required: false,
            validateCommand: "/opt/homebrew/bin/ffmpeg -version"
        )

        // Binary won't be found by path search (fake id), but
        // validateCommand starts with "/" so it gets tried directly
        let results = validator.validate(dependencies: [dep])
        XCTAssertEqual(results.count, 1)
        if case .found = results[0].status {
            // Good — found via direct validateCommand
        } else {
            XCTFail("Expected dependency found via validateCommand")
        }
    }

    // MARK: - Deduplication

    func testDeduplicatesByID() {
        let validator = DependencyValidator(
            commandRunner: { _ in false }
        )

        let dep1 = Dependency(id: "ffmpeg", kind: .helperBinary, required: false)
        let dep2 = Dependency(id: "ffmpeg", kind: .helperBinary, required: false)
        let dep3 = Dependency(id: "imagemagick", kind: .helperBinary, required: false)

        let results = validator.validate(dependencies: [dep1, dep2, dep3])
        XCTAssertEqual(results.count, 2) // ffmpeg + imagemagick, not 3
    }

    // MARK: - Library

    func testLibraryValidatedViaCommand() {
        let validator = DependencyValidator(
            commandRunner: { command in
                command == "pkg-config --exists libmagic"
            }
        )

        let dep = Dependency(
            id: "libmagic",
            kind: .library,
            required: true,
            validateCommand: "pkg-config --exists libmagic"
        )

        let results = validator.validate(dependencies: [dep])
        XCTAssertEqual(results.count, 1)
        if case .found = results[0].status {
            // Good
        } else {
            XCTFail("Expected library found via validateCommand")
        }
    }

    func testLibraryWithoutCommandIsMissing() {
        let validator = DependencyValidator(
            commandRunner: { _ in false }
        )

        let dep = Dependency(
            id: "libmagic",
            kind: .library,
            required: true
        )

        let results = validator.validate(dependencies: [dep])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].status, .missing)
        XCTAssertTrue(results[0].isBlocker)
    }

    // MARK: - Mixed Required + Optional

    func testMixedRequiredAndOptional() {
        let validator = DependencyValidator(
            commandRunner: { _ in false }
        )

        let required = Dependency(
            id: "required_missing_xyz",
            kind: .helperBinary,
            required: true
        )
        let optional = Dependency(
            id: "optional_missing_xyz",
            kind: .helperBinary,
            required: false
        )

        let results = validator.validate(dependencies: [required, optional])
        XCTAssertEqual(results.count, 2)

        let blockers = results.filter(\.isBlocker)
        let warnings = results.filter(\.isWarning)
        XCTAssertEqual(blockers.count, 1)
        XCTAssertEqual(blockers[0].dependency.id, "required_missing_xyz")
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings[0].dependency.id, "optional_missing_xyz")
    }

    // MARK: - Empty

    func testEmptyDependenciesReturnsEmpty() {
        let validator = DependencyValidator()
        let results = validator.validate(dependencies: [])
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Found Status

    func testFoundStatusIsNotBlockerOrWarning() {
        let dep = Dependency(id: "test", kind: .helperBinary, required: true)
        let result = DependencyResult(dependency: dep, status: .found(path: "/usr/bin/test"))
        XCTAssertFalse(result.isBlocker)
        XCTAssertFalse(result.isWarning)
    }
}
