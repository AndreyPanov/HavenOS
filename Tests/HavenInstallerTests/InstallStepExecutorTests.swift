import XCTest
import Foundation
import HavenCore
@testable import HavenInstaller

final class InstallStepExecutorTests: XCTestCase {

    private var tmpDir: URL!
    private var serviceRoot: URL!
    private let executor = InstallStepExecutor()
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        tmpDir = fm.temporaryDirectory
            .appendingPathComponent("haven-steps-test-\(UUID().uuidString)")
        serviceRoot = tmpDir.appendingPathComponent("service-root")
        try? fm.createDirectory(at: serviceRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - mkdir

    func testMkdirCreatesDirectory() throws {
        let dir = serviceRoot.appendingPathComponent("config").path
        let block = InstallBlock(steps: [
            InstallStep(action: .mkdir, path: dir)
        ])

        _ = try executor.execute(block: block, serviceRoot: serviceRoot)

        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: dir, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testMkdirCreatesNestedDirectories() throws {
        let dir = serviceRoot.appendingPathComponent("a/b/c").path
        let block = InstallBlock(steps: [
            InstallStep(action: .mkdir, path: dir)
        ])

        _ = try executor.execute(block: block, serviceRoot: serviceRoot)

        XCTAssertTrue(fm.fileExists(atPath: dir))
    }

    // MARK: - writeFile

    func testWriteFileCreatesFile() throws {
        let file = serviceRoot.appendingPathComponent("config.yaml").path
        let block = InstallBlock(steps: [
            InstallStep(action: .writeFile, path: file, content: "port: 8080\n")
        ])

        _ = try executor.execute(block: block, serviceRoot: serviceRoot)

        let content = try String(contentsOfFile: file, encoding: .utf8)
        XCTAssertEqual(content, "port: 8080\n")
    }

    func testWriteFileCreatesParentDirectories() throws {
        let file = serviceRoot.appendingPathComponent("nested/dir/config.yaml").path
        let block = InstallBlock(steps: [
            InstallStep(action: .writeFile, path: file, content: "hello")
        ])

        _ = try executor.execute(block: block, serviceRoot: serviceRoot)

        XCTAssertTrue(fm.fileExists(atPath: file))
    }

    // MARK: - copy

    func testCopyCopiesFile() throws {
        // Create a source file
        let sourceFile = serviceRoot.appendingPathComponent("source.bin")
        try "binary-data".write(to: sourceFile, atomically: true, encoding: .utf8)

        let dest = serviceRoot.appendingPathComponent("bin/app").path
        let block = InstallBlock(steps: [
            InstallStep(action: .copy, path: dest, source: sourceFile.path)
        ])

        _ = try executor.execute(block: block, serviceRoot: serviceRoot)

        XCTAssertTrue(fm.fileExists(atPath: dest))
        // Source should still exist
        XCTAssertTrue(fm.fileExists(atPath: sourceFile.path))
    }

    // MARK: - move

    func testMoveMovesFile() throws {
        let sourceFile = serviceRoot.appendingPathComponent("temp.bin")
        try "data".write(to: sourceFile, atomically: true, encoding: .utf8)

        let dest = serviceRoot.appendingPathComponent("final/app.bin").path
        let block = InstallBlock(steps: [
            InstallStep(action: .move, path: dest, source: sourceFile.path)
        ])

        _ = try executor.execute(block: block, serviceRoot: serviceRoot)

        XCTAssertTrue(fm.fileExists(atPath: dest))
        XCTAssertFalse(fm.fileExists(atPath: sourceFile.path))
    }

    // MARK: - chmod

    func testChmodSetsPermissions() throws {
        let file = serviceRoot.appendingPathComponent("script.sh")
        try "#!/bin/sh".write(to: file, atomically: true, encoding: .utf8)

        let block = InstallBlock(steps: [
            InstallStep(action: .chmod, path: file.path, mode: "755")
        ])

        _ = try executor.execute(block: block, serviceRoot: serviceRoot)

        let attrs = try fm.attributesOfItem(atPath: file.path)
        let perms = attrs[.posixPermissions] as? UInt16
        XCTAssertEqual(perms, 0o755)
    }

    func testChmodRejectsInvalidMode() throws {
        let file = serviceRoot.appendingPathComponent("file.txt")
        try "data".write(to: file, atomically: true, encoding: .utf8)

        let block = InstallBlock(steps: [
            InstallStep(action: .chmod, path: file.path, mode: "xyz")
        ])

        XCTAssertThrowsError(try executor.execute(block: block, serviceRoot: serviceRoot))
    }

    // MARK: - symlink

    func testSymlinkCreatesLink() throws {
        let target = serviceRoot.appendingPathComponent("real-file")
        try "content".write(to: target, atomically: true, encoding: .utf8)

        let link = serviceRoot.appendingPathComponent("link-file").path
        let block = InstallBlock(steps: [
            InstallStep(action: .symlink, path: link, source: target.path)
        ])

        _ = try executor.execute(block: block, serviceRoot: serviceRoot)

        let attrs = try fm.attributesOfItem(atPath: link)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)
    }

    // MARK: - generateSecret

    func testGenerateSecretProducesHexByDefault() throws {
        let block = InstallBlock(steps: [
            InstallStep(action: .generateSecret, path: "api_key", content: "16")
        ])

        let result = try executor.execute(block: block, serviceRoot: serviceRoot)

        let secret = result.generatedSecrets["api_key"]
        XCTAssertNotNil(secret)
        // 16 bytes = 32 hex chars
        XCTAssertEqual(secret?.count, 32)
        // Must be valid hex
        XCTAssertNotNil(UInt64(secret!.prefix(16), radix: 16))
    }

    func testGenerateSecretBase64() throws {
        let block = InstallBlock(steps: [
            InstallStep(action: .generateSecret, path: "token", mode: "base64", content: "32")
        ])

        let result = try executor.execute(block: block, serviceRoot: serviceRoot)

        let secret = result.generatedSecrets["token"]
        XCTAssertNotNil(secret)
        // Must be valid base64
        XCTAssertNotNil(Data(base64Encoded: secret!))
    }

    func testGenerateSecretInjectsIntoSubsequentSteps() throws {
        let configFile = serviceRoot.appendingPathComponent("config.ini").path
        let block = InstallBlock(steps: [
            InstallStep(action: .generateSecret, path: "secret_key", content: "8"),
            InstallStep(action: .writeFile, path: configFile, content: "key=${secret_key}")
        ])

        let result = try executor.execute(block: block, serviceRoot: serviceRoot)

        let secret = result.generatedSecrets["secret_key"]!
        let fileContent = try String(contentsOfFile: configFile, encoding: .utf8)
        XCTAssertEqual(fileContent, "key=\(secret)")
    }

    // MARK: - cleanup

    func testCleanupRemovesFile() throws {
        let file = serviceRoot.appendingPathComponent("temp-archive.tar.gz")
        try "archive".write(to: file, atomically: true, encoding: .utf8)

        let block = InstallBlock(steps: [
            InstallStep(action: .cleanup, path: file.path)
        ])

        _ = try executor.execute(block: block, serviceRoot: serviceRoot)

        XCTAssertFalse(fm.fileExists(atPath: file.path))
    }

    func testCleanupToleratesMissingFile() throws {
        let file = serviceRoot.appendingPathComponent("nonexistent.txt").path
        let block = InstallBlock(steps: [
            InstallStep(action: .cleanup, path: file)
        ])

        // Should not throw
        _ = try executor.execute(block: block, serviceRoot: serviceRoot)
    }

    // MARK: - Path Safety

    func testRejectsPathOutsideServiceRoot() {
        let escapedPath = tmpDir.appendingPathComponent("outside/evil.txt").path
        let block = InstallBlock(steps: [
            InstallStep(action: .mkdir, path: escapedPath)
        ])

        XCTAssertThrowsError(try executor.execute(block: block, serviceRoot: serviceRoot)) { error in
            guard let stepError = error as? InstallStepError else {
                return XCTFail("Expected InstallStepError, got \(error)")
            }
            if case .pathEscapesRoot = stepError {
                // Expected
            } else {
                XCTFail("Expected pathEscapesRoot, got \(stepError)")
            }
        }
    }

    func testRejectsPathTraversal() {
        let traversalPath = serviceRoot.appendingPathComponent("../../../etc/passwd").path
        let block = InstallBlock(steps: [
            InstallStep(action: .writeFile, path: traversalPath, content: "pwned")
        ])

        XCTAssertThrowsError(try executor.execute(block: block, serviceRoot: serviceRoot))
    }

    func testRejectsSiblingPathWithMatchingPrefix() {
        let sibling = URL(fileURLWithPath: serviceRoot.path + "-evil")
        let escapedPath = sibling.appendingPathComponent("payload.txt").path
        let block = InstallBlock(steps: [
            InstallStep(action: .writeFile, path: escapedPath, content: "pwned")
        ])

        XCTAssertThrowsError(try executor.execute(block: block, serviceRoot: serviceRoot)) { error in
            guard case .pathEscapesRoot = error as? InstallStepError else {
                return XCTFail("Expected pathEscapesRoot, got \(error)")
            }
        }
    }

    func testRejectsCopySourceOutsideServiceRoot() throws {
        let outsideSource = tmpDir.appendingPathComponent("outside-source.txt")
        try "secret".write(to: outsideSource, atomically: true, encoding: .utf8)
        let dest = serviceRoot.appendingPathComponent("copied.txt").path
        let block = InstallBlock(steps: [
            InstallStep(action: .copy, path: dest, source: outsideSource.path)
        ])

        XCTAssertThrowsError(try executor.execute(block: block, serviceRoot: serviceRoot)) { error in
            guard case .pathEscapesRoot = error as? InstallStepError else {
                return XCTFail("Expected pathEscapesRoot, got \(error)")
            }
        }
    }

    func testAllowsExplicitExternalSourcePath() throws {
        let externalRoot = tmpDir.appendingPathComponent("external")
        try fm.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        let source = externalRoot.appendingPathComponent("source.txt")
        try "external".write(to: source, atomically: true, encoding: .utf8)
        let dest = serviceRoot.appendingPathComponent("copied.txt").path
        let block = InstallBlock(steps: [
            InstallStep(action: .copy, path: dest, source: source.path)
        ])

        _ = try executor.execute(
            block: block,
            serviceRoot: serviceRoot,
            allowedExternalPaths: [externalRoot.path]
        )

        XCTAssertEqual(try String(contentsOfFile: dest), "external")
    }

    // MARK: - Rollback

    func testRollbackRemovesCreatedFiles() throws {
        let goodFile = serviceRoot.appendingPathComponent("good.txt").path
        let badPath = tmpDir.appendingPathComponent("outside/bad.txt").path // outside root

        let block = InstallBlock(steps: [
            InstallStep(action: .writeFile, path: goodFile, content: "hello"),
            InstallStep(action: .writeFile, path: badPath, content: "fail") // will fail path check
        ])

        XCTAssertThrowsError(try executor.execute(block: block, serviceRoot: serviceRoot))

        // The first file should have been rolled back
        XCTAssertFalse(fm.fileExists(atPath: goodFile))
    }

    func testRollbackRestoresOverwrittenFile() throws {
        let file = serviceRoot.appendingPathComponent("config.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)

        let badPath = tmpDir.appendingPathComponent("outside.txt").path

        let block = InstallBlock(steps: [
            InstallStep(action: .writeFile, path: file.path, content: "modified"),
            InstallStep(action: .writeFile, path: badPath, content: "fail")
        ])

        XCTAssertThrowsError(try executor.execute(block: block, serviceRoot: serviceRoot))

        // Original content should be restored
        let restored = try String(contentsOfFile: file.path, encoding: .utf8)
        XCTAssertEqual(restored, "original")
    }

    func testRollbackReversesMoveOnFailure() throws {
        let sourceFile = serviceRoot.appendingPathComponent("source.txt")
        try "data".write(to: sourceFile, atomically: true, encoding: .utf8)
        let dest = serviceRoot.appendingPathComponent("dest.txt").path
        let badPath = tmpDir.appendingPathComponent("outside.txt").path

        let block = InstallBlock(steps: [
            InstallStep(action: .move, path: dest, source: sourceFile.path),
            InstallStep(action: .writeFile, path: badPath, content: "fail")
        ])

        XCTAssertThrowsError(try executor.execute(block: block, serviceRoot: serviceRoot))

        // Source should be restored
        XCTAssertTrue(fm.fileExists(atPath: sourceFile.path))
        XCTAssertFalse(fm.fileExists(atPath: dest))
    }

    // MARK: - Missing Source

    func testCopyWithoutSourceThrows() {
        let dest = serviceRoot.appendingPathComponent("file.txt").path
        let block = InstallBlock(steps: [
            InstallStep(action: .copy, path: dest)
        ])

        XCTAssertThrowsError(try executor.execute(block: block, serviceRoot: serviceRoot)) { error in
            guard let stepError = error as? InstallStepError else {
                return XCTFail("Expected InstallStepError")
            }
            if case .missingSource = stepError {
                // Expected
            } else {
                XCTFail("Expected missingSource, got \(stepError)")
            }
        }
    }

    // MARK: - Template Expansion

    func testTemplateExpansionInSteps() throws {
        let context = TemplateContext(values: [
            "config_dir": serviceRoot.appendingPathComponent("config").path,
            "port": "8080"
        ])

        let block = InstallBlock(steps: [
            InstallStep(action: .mkdir, path: "${config_dir}"),
            InstallStep(action: .writeFile, path: "${config_dir}/app.yaml", content: "port: ${port}")
        ])

        _ = try executor.execute(
            block: block,
            serviceRoot: serviceRoot,
            templateContext: context
        )

        let configDir = serviceRoot.appendingPathComponent("config")
        XCTAssertTrue(fm.fileExists(atPath: configDir.path))

        let content = try String(
            contentsOfFile: configDir.appendingPathComponent("app.yaml").path,
            encoding: .utf8
        )
        XCTAssertEqual(content, "port: 8080")
    }

    // MARK: - Empty Block

    func testEmptyBlockSucceeds() throws {
        let block = InstallBlock(steps: [])
        let result = try executor.execute(block: block, serviceRoot: serviceRoot)
        XCTAssertTrue(result.generatedSecrets.isEmpty)
    }

    // MARK: - Multi-step Integration

    func testFullInstallFlow() throws {
        let binDir = serviceRoot.appendingPathComponent("bin").path
        let configDir = serviceRoot.appendingPathComponent("config").path
        let configFile = serviceRoot.appendingPathComponent("config/app.ini").path

        let block = InstallBlock(steps: [
            InstallStep(action: .mkdir, path: binDir),
            InstallStep(action: .mkdir, path: configDir),
            InstallStep(action: .generateSecret, path: "api_key", content: "16"),
            InstallStep(action: .writeFile, path: configFile, content: "secret=${api_key}\nport=8080"),
        ])

        let result = try executor.execute(block: block, serviceRoot: serviceRoot)

        XCTAssertTrue(fm.fileExists(atPath: binDir))
        XCTAssertTrue(fm.fileExists(atPath: configDir))

        let secret = result.generatedSecrets["api_key"]!
        let content = try String(contentsOfFile: configFile, encoding: .utf8)
        XCTAssertEqual(content, "secret=\(secret)\nport=8080")
    }
}
