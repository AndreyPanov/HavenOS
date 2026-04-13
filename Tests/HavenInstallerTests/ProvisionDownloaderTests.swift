import XCTest
import Foundation
import HavenCore
@testable import HavenInstaller

final class ProvisionDownloaderTests: XCTestCase {

    private var tmpDir: URL!
    private var serviceRoot: URL!
    private let downloader = ProvisionDownloader()

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-provision-test-\(UUID().uuidString)")
        serviceRoot = tmpDir.appendingPathComponent("service-root")
        try? FileManager.default.createDirectory(
            at: serviceRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Path Safety

    func testRejectsPathEscapingServiceRoot() {
        let provision = Provision(
            description: "Escape attempt",
            source: "https://example.com/file",
            destination: serviceRoot
                .deletingLastPathComponent()
                .appendingPathComponent("outside/evil.txt").path
        )

        XCTAssertThrowsError(try downloader.execute(
            provision: provision,
            serviceRoot: serviceRoot
        )) { error in
            guard case ProvisionError.pathEscapesServiceRoot = error else {
                XCTFail("Expected pathEscapesServiceRoot, got \(error)")
                return
            }
        }
    }

    func testRejectsPathWithDotDotComponents() {
        let provision = Provision(
            description: "Dot-dot escape",
            source: "https://example.com/file",
            destination: serviceRoot
                .appendingPathComponent("data/../../../etc/passwd").path
        )

        XCTAssertThrowsError(try downloader.execute(
            provision: provision,
            serviceRoot: serviceRoot
        )) { error in
            guard case ProvisionError.pathEscapesServiceRoot = error else {
                XCTFail("Expected pathEscapesServiceRoot, got \(error)")
                return
            }
        }
    }

    // MARK: - Idempotency

    func testSkipsExistingFile() throws {
        let destPath = serviceRoot.appendingPathComponent("data/existing.db")
        try FileManager.default.createDirectory(
            at: destPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let originalContent = "original content".data(using: .utf8)!
        try originalContent.write(to: destPath)

        let provision = Provision(
            description: "Already exists",
            source: "https://example.com/new.db",
            destination: destPath.path
        )

        // Should not throw, and file should be unchanged
        try downloader.execute(provision: provision, serviceRoot: serviceRoot)

        let afterContent = try Data(contentsOf: destPath)
        XCTAssertEqual(afterContent, originalContent, "Existing file should not be overwritten")
    }

    // MARK: - Atomic Write

    func testCleanupOnInvalidSource() {
        let destPath = serviceRoot.appendingPathComponent("data/test.db")
        let provision = Provision(
            description: "Bad source",
            source: "not-a-valid-url",
            destination: destPath.path
        )

        XCTAssertThrowsError(try downloader.execute(
            provision: provision,
            serviceRoot: serviceRoot
        )) { error in
            guard case ProvisionError.downloadFailed = error else {
                XCTFail("Expected downloadFailed, got \(error)")
                return
            }
        }

        // No leftover files at destination or temp location
        XCTAssertFalse(FileManager.default.fileExists(atPath: destPath.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destPath.path + ".downloading")
        )
    }

    func testSuccessfulLocalFileDownload() throws {
        // Create a local "source" file to download from (file:// URL)
        let sourceFile = tmpDir.appendingPathComponent("source.db")
        let sourceData = "hello haven".data(using: .utf8)!
        try sourceData.write(to: sourceFile)

        let destPath = serviceRoot.appendingPathComponent("data/metadata.db")
        let provision = Provision(
            description: "Local file",
            source: sourceFile.absoluteString,
            destination: destPath.path
        )

        try downloader.execute(provision: provision, serviceRoot: serviceRoot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destPath.path))
        let destData = try Data(contentsOf: destPath)
        XCTAssertEqual(destData, sourceData)

        // No temp file should remain
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destPath.path + ".downloading")
        )
    }

    // MARK: - Parent Directory Creation

    func testCreatesParentDirectories() throws {
        let sourceFile = tmpDir.appendingPathComponent("source.txt")
        try "data".data(using: .utf8)!.write(to: sourceFile)

        let destPath = serviceRoot
            .appendingPathComponent("deep/nested/dir/file.txt")
        let provision = Provision(
            description: "Deep nested",
            source: sourceFile.absoluteString,
            destination: destPath.path
        )

        try downloader.execute(provision: provision, serviceRoot: serviceRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destPath.path))
    }
}
