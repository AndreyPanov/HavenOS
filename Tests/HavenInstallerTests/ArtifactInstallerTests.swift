import XCTest
import Foundation
import HavenCore
@testable import HavenInstaller

// MARK: - MockDownloadClient

final class MockDownloadClient: DownloadClient, @unchecked Sendable {

    /// Map of remote URLs to local fixture files that should be "returned".
    var responses: [URL: URL] = [:]

    /// If set, download will throw this error.
    var error: Error?

    private(set) var downloadedURLs: [URL] = []

    func download(from url: URL) throws -> URL {
        downloadedURLs.append(url)
        if let error = error {
            throw error
        }
        guard let localURL = responses[url] else {
            throw URLError(.fileDoesNotExist)
        }
        return localURL
    }
}

// MARK: - MockArchiveExtractor

final class MockArchiveExtractor: ArchiveExtractor, @unchecked Sendable {

    struct Call: Equatable {
        let archiveURL: URL
        let destinationDirectory: URL
        let format: ArtifactFormat
    }

    private(set) var calls: [Call] = []

    /// If set, extract will throw this error.
    var error: Error?

    /// If true, create a marker file in the destination to simulate extraction.
    var simulateExtraction = true

    func extract(
        archiveURL: URL,
        to destinationDirectory: URL,
        format: ArtifactFormat
    ) throws {
        calls.append(Call(
            archiveURL: archiveURL,
            destinationDirectory: destinationDirectory,
            format: format
        ))
        if let error = error {
            throw error
        }
        if simulateExtraction {
            try FileManager.default.createDirectory(
                at: destinationDirectory,
                withIntermediateDirectories: true
            )
            // Create a marker file to simulate extracted content
            let marker = destinationDirectory.appendingPathComponent("extracted-marker")
            try Data("extracted".utf8).write(to: marker)
        }
    }
}

// MARK: - ArtifactSource Tests

final class ArtifactSourceTests: XCTestCase {

    func testLocalSource() {
        let url = URL(fileURLWithPath: "/tmp/artifact.zip")
        let source = ArtifactSource.local(url)
        XCTAssertEqual(source, .local(url))
    }

    func testRemoteSource() {
        let url = URL(string: "https://example.com/artifact.zip")!
        let source = ArtifactSource.remote(url)
        XCTAssertEqual(source, .remote(url))
    }

    func testStringInitHTTPS() {
        let source = ArtifactSource(string: "https://example.com/app.zip")
        if case .remote(let url) = source {
            XCTAssertEqual(url.absoluteString, "https://example.com/app.zip")
        } else {
            XCTFail("Expected remote source")
        }
    }

    func testStringInitHTTP() {
        let source = ArtifactSource(string: "http://example.com/app.zip")
        if case .remote(let url) = source {
            XCTAssertEqual(url.absoluteString, "http://example.com/app.zip")
        } else {
            XCTFail("Expected remote source")
        }
    }

    func testStringInitLocalPath() {
        let source = ArtifactSource(string: "/opt/haven/artifacts/app")
        if case .local(let url) = source {
            XCTAssertEqual(url.path, "/opt/haven/artifacts/app")
        } else {
            XCTFail("Expected local source")
        }
    }

    func testEquality() {
        let a = ArtifactSource(string: "https://example.com/app.zip")
        let b = ArtifactSource(string: "https://example.com/app.zip")
        XCTAssertEqual(a, b)
    }
}

// MARK: - ArtifactFormat Tests

final class ArtifactFormatTests: XCTestCase {

    func testDetectZip() {
        XCTAssertEqual(ArtifactFormat.detect(from: "app.zip"), .zip)
        XCTAssertEqual(ArtifactFormat.detect(from: "APP.ZIP"), .zip)
    }

    func testDetectTarGz() {
        XCTAssertEqual(ArtifactFormat.detect(from: "app.tar.gz"), .tarGz)
        XCTAssertEqual(ArtifactFormat.detect(from: "APP.TAR.GZ"), .tarGz)
        XCTAssertEqual(ArtifactFormat.detect(from: "app.tgz"), .tarGz)
    }

    func testDetectUnknown() {
        XCTAssertNil(ArtifactFormat.detect(from: "app"))
        XCTAssertNil(ArtifactFormat.detect(from: "app.dmg"))
        XCTAssertNil(ArtifactFormat.detect(from: "app.pkg"))
    }

    func testEquality() {
        XCTAssertEqual(ArtifactFormat.zip, .zip)
        XCTAssertEqual(ArtifactFormat.tarGz, .tarGz)
        XCTAssertEqual(ArtifactFormat.executable, .executable)
        XCTAssertNotEqual(ArtifactFormat.zip, .tarGz)
    }
}

// MARK: - ArtifactDescriptor Tests

final class ArtifactDescriptorTests: XCTestCase {

    func testProperties() {
        let desc = ArtifactDescriptor(
            unitID: "haven.unit.test-db",
            source: .local(URL(fileURLWithPath: "/tmp/db.zip")),
            format: .zip
        )
        XCTAssertEqual(desc.unitID, "haven.unit.test-db")
        XCTAssertEqual(desc.format, .zip)
    }

    func testEquality() {
        let a = ArtifactDescriptor(
            unitID: "u.1",
            source: .local(URL(fileURLWithPath: "/tmp/x")),
            format: .executable
        )
        let b = ArtifactDescriptor(
            unitID: "u.1",
            source: .local(URL(fileURLWithPath: "/tmp/x")),
            format: .executable
        )
        XCTAssertEqual(a, b)
    }
}

// MARK: - ArtifactInstallResult Tests

final class ArtifactInstallResultTests: XCTestCase {

    func testProperties() {
        let result = ArtifactInstallResult(
            unitID: "u.1",
            installDirectory: URL(fileURLWithPath: "/tmp/installed/u.1"),
            wasCached: false
        )
        XCTAssertEqual(result.unitID, "u.1")
        XCTAssertFalse(result.wasCached)
    }

    func testEquality() {
        let a = ArtifactInstallResult(
            unitID: "u.1",
            installDirectory: URL(fileURLWithPath: "/tmp/x"),
            wasCached: true
        )
        let b = ArtifactInstallResult(
            unitID: "u.1",
            installDirectory: URL(fileURLWithPath: "/tmp/x"),
            wasCached: true
        )
        XCTAssertEqual(a, b)
    }
}

// MARK: - ArtifactInstallerError Tests

final class ArtifactInstallerErrorTests: XCTestCase {

    func testEquality() {
        let a = ArtifactInstallerError.sourceFileNotFound(unitID: "u", path: "/x")
        let b = ArtifactInstallerError.sourceFileNotFound(unitID: "u", path: "/x")
        XCTAssertEqual(a, b)
    }

    func testInequality() {
        let a = ArtifactInstallerError.sourceFileNotFound(unitID: "u", path: "/x")
        let b = ArtifactInstallerError.downloadFailed(unitID: "u", url: "/x", detail: "d")
        XCTAssertNotEqual(a, b)
    }

    func testNoToolingLeaksInErrorCases() {
        let errors: [ArtifactInstallerError] = [
            .sourceFileNotFound(unitID: "u", path: "/x"),
            .downloadFailed(unitID: "u", url: "http://x", detail: "d"),
            .extractionFailed(unitID: "u", detail: "d"),
            .unsupportedFormat(unitID: "u", detail: "d"),
            .artifactNotFound(unitID: "u", path: "/x"),
            .installFailed(unitID: "u", detail: "d"),
        ]
        let forbidden = ["pip", "python", "brew", "PATH", "launchctl", "venv", "tar", "ditto", "unzip"]

        for error in errors {
            let description = String(describing: error)
            let casePrefix = description.prefix(while: { $0 != "(" })
            for word in forbidden {
                XCTAssertFalse(
                    casePrefix.contains(word),
                    "Error case name should not contain '\(word)': \(casePrefix)"
                )
            }
        }
    }
}

// MARK: - ArtifactCache Tests

final class ArtifactCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-cache-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInstallDirectory() {
        let cache = ArtifactCache(installedRoot: tempDir)
        let dir = cache.installDirectory(for: "haven.unit.test-db")
        XCTAssertEqual(dir, tempDir.appendingPathComponent("haven.unit.test-db", isDirectory: true))
    }

    func testNotCachedInitially() {
        let cache = ArtifactCache(installedRoot: tempDir)
        XCTAssertFalse(cache.isCached(unitID: "haven.unit.test-db"))
    }

    func testCachedAfterPrepareAndContent() throws {
        let cache = ArtifactCache(installedRoot: tempDir)
        let dir = try cache.prepareCleanDirectory(for: "haven.unit.test-db")
        // Write a file to make it non-empty
        try Data("content".utf8).write(to: dir.appendingPathComponent("artifact"))
        XCTAssertTrue(cache.isCached(unitID: "haven.unit.test-db"))
    }

    func testNotCachedWhenDirectoryEmpty() throws {
        let cache = ArtifactCache(installedRoot: tempDir)
        _ = try cache.prepareCleanDirectory(for: "haven.unit.test-db")
        // Directory exists but is empty
        XCTAssertFalse(cache.isCached(unitID: "haven.unit.test-db"))
    }

    func testRemove() throws {
        let cache = ArtifactCache(installedRoot: tempDir)
        let dir = try cache.prepareCleanDirectory(for: "haven.unit.test-db")
        try Data("content".utf8).write(to: dir.appendingPathComponent("artifact"))
        XCTAssertTrue(cache.isCached(unitID: "haven.unit.test-db"))

        try cache.remove(unitID: "haven.unit.test-db")
        XCTAssertFalse(cache.isCached(unitID: "haven.unit.test-db"))
    }

    func testRemoveNonexistentIsNoOp() throws {
        let cache = ArtifactCache(installedRoot: tempDir)
        XCTAssertNoThrow(try cache.remove(unitID: "nonexistent"))
    }

    func testPrepareCleanDirectoryRemovesExisting() throws {
        let cache = ArtifactCache(installedRoot: tempDir)
        let dir1 = try cache.prepareCleanDirectory(for: "haven.unit.test-db")
        try Data("old".utf8).write(to: dir1.appendingPathComponent("old-file"))

        let dir2 = try cache.prepareCleanDirectory(for: "haven.unit.test-db")
        XCTAssertEqual(dir1, dir2)
        // Old file should be gone
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: dir2.appendingPathComponent("old-file").path
            )
        )
    }

    func testInstallDirectoryIsDeterministic() {
        let cache = ArtifactCache(installedRoot: tempDir)
        let a = cache.installDirectory(for: "u.1")
        let b = cache.installDirectory(for: "u.1")
        XCTAssertEqual(a, b)
    }
}

// MARK: - ArtifactInstaller Install from Local Executable Tests

final class ArtifactInstallerExecutableTests: XCTestCase {

    private var tempDir: URL!
    private var installedDir: URL!
    private var downloadsDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-install-test-\(UUID().uuidString)")
        installedDir = tempDir.appendingPathComponent("Installed")
        downloadsDir = tempDir.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: installedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInstallLocalExecutable() throws {
        // Create a fixture executable
        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let execFixture = fixtureDir.appendingPathComponent("test-db")
        try Data("#!/bin/sh\necho hello".utf8).write(to: execFixture)

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: MockArchiveExtractor(),
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test-db",
            source: .local(execFixture),
            format: .executable
        )

        let result = try installer.install(descriptor: descriptor)

        XCTAssertEqual(result.unitID, "haven.unit.test-db")
        XCTAssertFalse(result.wasCached)
        XCTAssertEqual(result.installDirectory, installedDir.appendingPathComponent("haven.unit.test-db", isDirectory: true))

        // Verify the file was copied
        let installed = result.installDirectory.appendingPathComponent("test-db")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))

        // Verify it's executable
        let attrs = try FileManager.default.attributesOfItem(atPath: installed.path)
        let perms = attrs[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o755)
    }

    func testInstallLocalExecutableNotFound() {
        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: MockArchiveExtractor(),
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test-db",
            source: .local(URL(fileURLWithPath: "/nonexistent/test-db")),
            format: .executable
        )

        XCTAssertThrowsError(try installer.install(descriptor: descriptor)) { error in
            guard case .sourceFileNotFound(let unitID, _) = error as? ArtifactInstallerError else {
                XCTFail("Expected sourceFileNotFound, got \(error)")
                return
            }
            XCTAssertEqual(unitID, "haven.unit.test-db")
        }
    }
}

// MARK: - ArtifactInstaller Install from Archive Tests

final class ArtifactInstallerArchiveTests: XCTestCase {

    private var tempDir: URL!
    private var installedDir: URL!
    private var downloadsDir: URL!
    private var mockExtractor: MockArchiveExtractor!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-install-test-\(UUID().uuidString)")
        installedDir = tempDir.appendingPathComponent("Installed")
        downloadsDir = tempDir.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: installedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        mockExtractor = MockArchiveExtractor()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInstallLocalZipArchive() throws {
        // Create a fixture zip file (mock extractor doesn't need it to be real)
        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let zipFixture = fixtureDir.appendingPathComponent("app.zip")
        try Data("fake-zip".utf8).write(to: zipFixture)

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: mockExtractor,
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test-web",
            source: .local(zipFixture),
            format: .zip
        )

        let result = try installer.install(descriptor: descriptor)

        XCTAssertEqual(result.unitID, "haven.unit.test-web")
        XCTAssertFalse(result.wasCached)

        // Verify extractor was called with correct format
        XCTAssertEqual(mockExtractor.calls.count, 1)
        XCTAssertEqual(mockExtractor.calls[0].format, .zip)
        XCTAssertEqual(mockExtractor.calls[0].archiveURL, zipFixture)
    }

    func testInstallLocalTarGzArchive() throws {
        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let tarFixture = fixtureDir.appendingPathComponent("app.tar.gz")
        try Data("fake-tar".utf8).write(to: tarFixture)

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: mockExtractor,
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test-worker",
            source: .local(tarFixture),
            format: .tarGz
        )

        let result = try installer.install(descriptor: descriptor)

        XCTAssertEqual(result.unitID, "haven.unit.test-worker")
        XCTAssertFalse(result.wasCached)

        // Verify extractor was called with correct format
        XCTAssertEqual(mockExtractor.calls.count, 1)
        XCTAssertEqual(mockExtractor.calls[0].format, .tarGz)
    }

    func testExtractionFailureReturnsStructuredError() throws {
        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let badArchive = fixtureDir.appendingPathComponent("bad.zip")
        try Data("not-a-zip".utf8).write(to: badArchive)

        mockExtractor.error = ProcessArchiveExtractorError.extractionFailed(
            exitCode: 1, stderr: "invalid archive"
        )

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: mockExtractor,
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test-db",
            source: .local(badArchive),
            format: .zip
        )

        XCTAssertThrowsError(try installer.install(descriptor: descriptor)) { error in
            guard case .extractionFailed(let unitID, _) = error as? ArtifactInstallerError else {
                XCTFail("Expected extractionFailed, got \(error)")
                return
            }
            XCTAssertEqual(unitID, "haven.unit.test-db")
        }

        // Should clean up partial extraction
        XCTAssertFalse(cache.isCached(unitID: "haven.unit.test-db"))
    }
}

// MARK: - ArtifactInstaller Cache Tests

final class ArtifactInstallerCacheTests: XCTestCase {

    private var tempDir: URL!
    private var installedDir: URL!
    private var downloadsDir: URL!
    private var mockExtractor: MockArchiveExtractor!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-install-test-\(UUID().uuidString)")
        installedDir = tempDir.appendingPathComponent("Installed")
        downloadsDir = tempDir.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: installedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        mockExtractor = MockArchiveExtractor()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCacheHitAvoidsDuplicateExtraction() throws {
        // Pre-populate the cache
        let unitDir = installedDir.appendingPathComponent("haven.unit.test-db")
        try FileManager.default.createDirectory(at: unitDir, withIntermediateDirectories: true)
        try Data("cached-content".utf8).write(to: unitDir.appendingPathComponent("test-db"))

        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let execFixture = fixtureDir.appendingPathComponent("test-db")
        try Data("new-content".utf8).write(to: execFixture)

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: mockExtractor,
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test-db",
            source: .local(execFixture),
            format: .executable
        )

        let result = try installer.install(descriptor: descriptor)

        XCTAssertTrue(result.wasCached)
        XCTAssertEqual(result.installDirectory, installedDir.appendingPathComponent("haven.unit.test-db", isDirectory: true))
        // Extractor should not have been called
        XCTAssertEqual(mockExtractor.calls.count, 0)
    }

    func testUninstallRemovesCache() throws {
        // Install first
        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let execFixture = fixtureDir.appendingPathComponent("test-db")
        try Data("content".utf8).write(to: execFixture)

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: mockExtractor,
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test-db",
            source: .local(execFixture),
            format: .executable
        )

        _ = try installer.install(descriptor: descriptor)
        XCTAssertTrue(cache.isCached(unitID: "haven.unit.test-db"))

        try installer.uninstall(unitID: "haven.unit.test-db")
        XCTAssertFalse(cache.isCached(unitID: "haven.unit.test-db"))
    }
}

// MARK: - ArtifactInstaller Remote Download Tests

final class ArtifactInstallerDownloadTests: XCTestCase {

    private var tempDir: URL!
    private var installedDir: URL!
    private var downloadsDir: URL!
    private var mockDownload: MockDownloadClient!
    private var mockExtractor: MockArchiveExtractor!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-install-test-\(UUID().uuidString)")
        installedDir = tempDir.appendingPathComponent("Installed")
        downloadsDir = tempDir.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: installedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        mockDownload = MockDownloadClient()
        mockExtractor = MockArchiveExtractor()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInstallFromRemoteURL() throws {
        // Create a local fixture that the mock will return
        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let localFixture = fixtureDir.appendingPathComponent("downloaded.zip")
        try Data("fake-zip".utf8).write(to: localFixture)

        let remoteURL = URL(string: "https://example.com/app.zip")!
        mockDownload.responses[remoteURL] = localFixture

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDownload,
            extractor: mockExtractor,
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test-web",
            source: .remote(remoteURL),
            format: .zip
        )

        let result = try installer.install(descriptor: descriptor)

        XCTAssertEqual(result.unitID, "haven.unit.test-web")
        XCTAssertFalse(result.wasCached)
        XCTAssertEqual(mockDownload.downloadedURLs, [remoteURL])
        XCTAssertEqual(mockExtractor.calls.count, 1)
    }

    func testDownloadFailureReturnsStructuredError() {
        mockDownload.error = URLError(.notConnectedToInternet)

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDownload,
            extractor: mockExtractor,
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test-web",
            source: .remote(URL(string: "https://example.com/app.zip")!),
            format: .zip
        )

        XCTAssertThrowsError(try installer.install(descriptor: descriptor)) { error in
            guard case .downloadFailed(let unitID, _, _) = error as? ArtifactInstallerError else {
                XCTFail("Expected downloadFailed, got \(error)")
                return
            }
            XCTAssertEqual(unitID, "haven.unit.test-web")
        }
    }
}

// MARK: - ArtifactInstaller Deterministic Path Tests

final class ArtifactInstallerPathTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-path-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInstallDirectoryIsDeterministic() throws {
        let installedDir = tempDir.appendingPathComponent("Installed")
        try FileManager.default.createDirectory(at: installedDir, withIntermediateDirectories: true)

        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let execFixture = fixtureDir.appendingPathComponent("test-db")
        try Data("content".utf8).write(to: execFixture)

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: MockArchiveExtractor(),
            downloadsDirectory: tempDir.appendingPathComponent("Downloads")
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test-db",
            source: .local(execFixture),
            format: .executable
        )

        let result = try installer.install(descriptor: descriptor)
        let expected = installedDir.appendingPathComponent("haven.unit.test-db", isDirectory: true)
        XCTAssertEqual(result.installDirectory, expected)
    }

    func testHavenPathsConvenienceInit() {
        let paths = HavenPaths(base: tempDir)
        let installer = ArtifactInstaller(
            paths: paths,
            downloadClient: MockDownloadClient(),
            extractor: MockArchiveExtractor()
        )
        // Just verify it constructs without error
        _ = installer
    }
}

// MARK: - HavenPaths Installed Directory Tests

final class HavenPathsInstalledTests: XCTestCase {

    func testInstalledDirectory() {
        let paths = HavenPaths(base: URL(fileURLWithPath: "/tmp/haven-test"))
        XCTAssertEqual(paths.installedDirectory.path, "/tmp/haven-test/Installed")
    }

    func testInstalledDirectoryInTopLevel() {
        let paths = HavenPaths(base: URL(fileURLWithPath: "/tmp/haven-test"))
        let dirs = paths.topLevelDirectories.map(\.lastPathComponent)
        XCTAssertTrue(dirs.contains("Installed"))
    }
}

// MARK: - ProcessArchiveExtractor Real Integration Tests

final class ProcessArchiveExtractorTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-extractor-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testExtractRealZip() throws {
        // Create a real zip file using /usr/bin/ditto
        let sourceDir = tempDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: sourceDir.appendingPathComponent("file.txt"))

        let zipFile = tempDir.appendingPathComponent("test.zip")
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zipProcess.arguments = ["-ck", sourceDir.path, zipFile.path]
        try zipProcess.run()
        zipProcess.waitUntilExit()
        XCTAssertEqual(zipProcess.terminationStatus, 0)

        // Extract using our extractor
        let destDir = tempDir.appendingPathComponent("extracted")
        let extractor = ProcessArchiveExtractor()
        try extractor.extract(archiveURL: zipFile, to: destDir, format: .zip)

        // Verify extraction
        XCTAssertTrue(FileManager.default.fileExists(atPath: destDir.path))
        // ditto preserves directory structure, so look for file.txt
        let extractedFile = destDir.appendingPathComponent("file.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedFile.path))
        let content = try String(contentsOf: extractedFile, encoding: .utf8)
        XCTAssertEqual(content, "hello")
    }

    func testExtractRealTarGz() throws {
        // Create a real tar.gz file using /usr/bin/tar
        let sourceDir = tempDir.appendingPathComponent("tar-source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try Data("world".utf8).write(to: sourceDir.appendingPathComponent("data.txt"))

        let tarFile = tempDir.appendingPathComponent("test.tar.gz")
        let tarProcess = Process()
        tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProcess.arguments = ["-czf", tarFile.path, "-C", sourceDir.path, "."]
        try tarProcess.run()
        tarProcess.waitUntilExit()
        XCTAssertEqual(tarProcess.terminationStatus, 0)

        // Extract using our extractor
        let destDir = tempDir.appendingPathComponent("tar-extracted")
        let extractor = ProcessArchiveExtractor()
        try extractor.extract(archiveURL: tarFile, to: destDir, format: .tarGz)

        // Verify extraction
        let extractedFile = destDir.appendingPathComponent("data.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedFile.path))
        let content = try String(contentsOf: extractedFile, encoding: .utf8)
        XCTAssertEqual(content, "world")
    }

    func testExtractInvalidArchiveThrows() throws {
        let badFile = tempDir.appendingPathComponent("bad.zip")
        try Data("not a zip file".utf8).write(to: badFile)

        let destDir = tempDir.appendingPathComponent("bad-extract")
        let extractor = ProcessArchiveExtractor()

        XCTAssertThrowsError(
            try extractor.extract(archiveURL: badFile, to: destDir, format: .zip)
        ) { error in
            XCTAssertTrue(error is ProcessArchiveExtractorError)
        }
    }
}
