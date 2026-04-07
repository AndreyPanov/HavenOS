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
            // Create a marker file to simulate extracted content (executable)
            let marker = destinationDirectory.appendingPathComponent("extracted-marker")
            try Data("#!/bin/sh\necho extracted".utf8).write(to: marker)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: marker.path
            )
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
            .installFailed(unitID: "u", detail: "d"),
            .executableNotFound(unitID: "u", directory: "/x"),
            .invalidEntrypointPath(unitID: "u", path: "/abs/path"),
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
        // Pre-populate the cache with a valid executable
        let unitDir = installedDir.appendingPathComponent("haven.unit.test-db")
        try FileManager.default.createDirectory(at: unitDir, withIntermediateDirectories: true)
        let cachedFile = unitDir.appendingPathComponent("test-db")
        try Data("cached-content".utf8).write(to: cachedFile)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: cachedFile.path
        )

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

// MARK: - ArtifactInstaller stripFirstDirectory Tests

final class ArtifactInstallerStripTests: XCTestCase {

    private var tempDir: URL!
    private var installedDir: URL!
    private var downloadsDir: URL!
    private var mockExtractor: MockArchiveExtractor!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-strip-test-\(UUID().uuidString)")
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

    func testStripFirstDirectoryMovesContentsUp() throws {
        // Mock extractor that simulates an archive with a single top-level wrapper dir
        let ext = MockArchiveExtractor()
        ext.simulateExtraction = false

        let cache = ArtifactCache(installedRoot: installedDir)

        // Create a fixture archive file
        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let archiveFile = fixtureDir.appendingPathComponent("app.zip")
        try Data("fake-zip".utf8).write(to: archiveFile)

        // Configure the extractor to create a wrapped directory structure when called
        let wrappedDirName = "hello-service-v1.0.0"
        ext.simulateExtraction = false
        // We'll use a custom closure approach: override the extract behavior
        // by making the mock create the wrapped structure in the destination
        let customExtractor = WrappedDirectoryExtractor(
            wrapperName: wrappedDirName,
            files: [
                "hello-service": Data("#!/bin/sh\necho hello".utf8),
                "config.json": Data("{\"key\":\"value\"}".utf8),
            ]
        )

        let installerWithCustom = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: customExtractor,
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.hello",
            source: .local(archiveFile),
            format: .zip,
            stripFirstDirectory: true
        )

        let result = try installerWithCustom.install(descriptor: descriptor)

        // After stripping, the files should be at the top level
        let execPath = result.installDirectory.appendingPathComponent("hello-service")
        let configPath = result.installDirectory.appendingPathComponent("config.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: execPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))

        // The wrapper directory should be gone
        let wrapperPath = result.installDirectory.appendingPathComponent(wrappedDirName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wrapperPath.path))
    }

    func testStripFirstDirectoryNoOpWhenMultipleEntries() throws {
        // Extractor creates multiple top-level items — strip should be a no-op
        let ext = FlatFilesExtractor(files: [
            "app": Data("binary".utf8),
            "README.md": Data("readme".utf8),
        ])

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: ext,
            downloadsDirectory: downloadsDir
        )

        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let archiveFile = fixtureDir.appendingPathComponent("app.zip")
        try Data("fake-zip".utf8).write(to: archiveFile)

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.multi",
            source: .local(archiveFile),
            format: .zip,
            stripFirstDirectory: true
        )

        let result = try installer.install(descriptor: descriptor)

        // Both files should still be at top level (no change — strip is no-op)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.installDirectory.appendingPathComponent("app").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.installDirectory.appendingPathComponent("README.md").path
            )
        )
    }

    func testNoStripWhenFlagIsFalse() throws {
        // Extractor creates a wrapped directory but strip is disabled
        let ext = WrappedDirectoryExtractor(
            wrapperName: "inner",
            files: ["app": Data("binary".utf8)]
        )

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: ext,
            downloadsDirectory: downloadsDir
        )

        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let archiveFile = fixtureDir.appendingPathComponent("app.zip")
        try Data("fake-zip".utf8).write(to: archiveFile)

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.wrapped",
            source: .local(archiveFile),
            format: .zip,
            stripFirstDirectory: false
        )

        let result = try installer.install(descriptor: descriptor)

        // The wrapper directory should still be present
        let innerPath = result.installDirectory.appendingPathComponent("inner")
        XCTAssertTrue(FileManager.default.fileExists(atPath: innerPath.path))
    }
}

// MARK: - Test-only archive extractors

/// Simulates an archive that extracts with a single wrapper directory.
/// The first file in the `files` dictionary is made executable.
private final class WrappedDirectoryExtractor: ArchiveExtractor, @unchecked Sendable {
    let wrapperName: String
    let files: [String: Data]

    init(wrapperName: String, files: [String: Data]) {
        self.wrapperName = wrapperName
        self.files = files
    }

    func extract(archiveURL: URL, to destinationDirectory: URL, format: ArtifactFormat) throws {
        let wrapper = destinationDirectory.appendingPathComponent(wrapperName)
        try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
        var first = true
        for (name, data) in files {
            let path = wrapper.appendingPathComponent(name)
            try data.write(to: path)
            if first {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: path.path
                )
                first = false
            }
        }
    }
}

/// Simulates an archive that extracts flat files (no wrapper directory).
/// The first file in the `files` dictionary is made executable.
private final class FlatFilesExtractor: ArchiveExtractor, @unchecked Sendable {
    let files: [String: Data]

    init(files: [String: Data]) {
        self.files = files
    }

    func extract(archiveURL: URL, to destinationDirectory: URL, format: ArtifactFormat) throws {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        var first = true
        for (name, data) in files {
            let path = destinationDirectory.appendingPathComponent(name)
            try data.write(to: path)
            if first {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: path.path
                )
                first = false
            }
        }
    }
}

/// Simulates an archive that extracts but produces NO executable files.
private final class NoExecutableExtractor: ArchiveExtractor, @unchecked Sendable {

    func extract(archiveURL: URL, to destinationDirectory: URL, format: ArtifactFormat) throws {
        try FileManager.default.createDirectory(
            at: destinationDirectory, withIntermediateDirectories: true
        )
        // Create a non-executable file
        let dataFile = destinationDirectory.appendingPathComponent("data.txt")
        try Data("just data".utf8).write(to: dataFile)
    }
}

/// Simulates an archive that extracts a named executable.
private final class NamedExecutableExtractor: ArchiveExtractor, @unchecked Sendable {
    let executableName: String

    init(executableName: String) {
        self.executableName = executableName
    }

    func extract(archiveURL: URL, to destinationDirectory: URL, format: ArtifactFormat) throws {
        try FileManager.default.createDirectory(
            at: destinationDirectory, withIntermediateDirectories: true
        )
        let execFile = destinationDirectory.appendingPathComponent(executableName)
        try Data("#!/bin/sh\necho hello".utf8).write(to: execFile)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: execFile.path
        )
    }
}

/// Extractor that always fails.
private final class FailingExtractor: ArchiveExtractor, @unchecked Sendable {
    func extract(archiveURL: URL, to destinationDirectory: URL, format: ArtifactFormat) throws {
        throw ProcessArchiveExtractorError.extractionFailed(exitCode: 1, stderr: "simulated failure")
    }
}

// MARK: - Atomic Staging Tests

final class ArtifactInstallerAtomicTests: XCTestCase {

    private var tempDir: URL!
    private var installedDir: URL!
    private var downloadsDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-atomic-test-\(UUID().uuidString)")
        installedDir = tempDir.appendingPathComponent("Installed")
        downloadsDir = tempDir.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: installedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeFixtureFile(_ name: String = "app.zip") throws -> URL {
        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let file = fixtureDir.appendingPathComponent(name)
        try Data("fake-archive".utf8).write(to: file)
        return file
    }

    func testExtractionFailureLeavesNoFinalDirectory() throws {
        let archive = try makeFixtureFile()
        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: MockDownloadClient(),
            extractor: FailingExtractor(),
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(URL(string: "https://example.com/app.zip")!),
            format: .zip
        )

        // Set up mock download to return the fixture
        let mockDl = MockDownloadClient()
        mockDl.responses[URL(string: "https://example.com/app.zip")!] = archive
        let installer2 = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDl,
            extractor: FailingExtractor(),
            downloadsDirectory: downloadsDir
        )

        XCTAssertThrowsError(try installer2.install(descriptor: descriptor))

        // Final directory should not exist
        XCTAssertFalse(cache.isCached(unitID: "haven.unit.test"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: cache.installDirectory(for: "haven.unit.test").path
            )
        )
        // Staging directory should be cleaned up
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: cache.stagingDirectory(for: "haven.unit.test").path
            )
        )
    }

    func testSuccessfulAtomicInstallCreatesFinalDirectory() throws {
        let archive = try makeFixtureFile()
        let mockDl = MockDownloadClient()
        let remoteURL = URL(string: "https://example.com/app.zip")!
        mockDl.responses[remoteURL] = archive

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDl,
            extractor: NamedExecutableExtractor(executableName: "my-app"),
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip
        )

        let result = try installer.install(descriptor: descriptor)

        XCTAssertFalse(result.wasCached)
        XCTAssertTrue(cache.isCached(unitID: "haven.unit.test"))
        // Staging directory should be gone
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: cache.stagingDirectory(for: "haven.unit.test").path
            )
        )
        // Executable should be in the final directory
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.installDirectory.appendingPathComponent("my-app").path
            )
        )
    }

    func testForceReinstallBypassesCache() throws {
        let archive = try makeFixtureFile()

        // Pre-populate the cache
        let unitDir = installedDir.appendingPathComponent("haven.unit.test")
        try FileManager.default.createDirectory(at: unitDir, withIntermediateDirectories: true)
        let oldExec = unitDir.appendingPathComponent("old-binary")
        try Data("old".utf8).write(to: oldExec)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldExec.path)

        let mockDl = MockDownloadClient()
        let remoteURL = URL(string: "https://example.com/app.zip")!
        mockDl.responses[remoteURL] = archive

        let cache = ArtifactCache(installedRoot: installedDir)
        XCTAssertTrue(cache.isCached(unitID: "haven.unit.test"))

        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDl,
            extractor: NamedExecutableExtractor(executableName: "new-binary"),
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip
        )

        let result = try installer.install(descriptor: descriptor, forceReinstall: true)

        XCTAssertFalse(result.wasCached)
        // New binary should be present
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.installDirectory.appendingPathComponent("new-binary").path
            )
        )
        // Old binary should be gone
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: result.installDirectory.appendingPathComponent("old-binary").path
            )
        )
        // Download should have been called
        XCTAssertEqual(mockDl.downloadedURLs, [remoteURL])
    }
}

// MARK: - Post-extraction Validation Tests

final class ArtifactInstallerValidationTests: XCTestCase {

    private var tempDir: URL!
    private var installedDir: URL!
    private var downloadsDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-validation-test-\(UUID().uuidString)")
        installedDir = tempDir.appendingPathComponent("Installed")
        downloadsDir = tempDir.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: installedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeFixtureFile() throws -> URL {
        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let file = fixtureDir.appendingPathComponent("app.zip")
        try Data("fake-archive".utf8).write(to: file)
        return file
    }

    func testValidationFailsWhenNoExecutableFound() throws {
        let archive = try makeFixtureFile()
        let mockDl = MockDownloadClient()
        let remoteURL = URL(string: "https://example.com/app.zip")!
        mockDl.responses[remoteURL] = archive

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDl,
            extractor: NoExecutableExtractor(),
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip
        )

        XCTAssertThrowsError(try installer.install(descriptor: descriptor)) { error in
            guard case .executableNotFound(let unitID, _) = error as? ArtifactInstallerError else {
                XCTFail("Expected executableNotFound, got \(error)")
                return
            }
            XCTAssertEqual(unitID, "haven.unit.test")
        }
        // Should clean up staging
        XCTAssertFalse(cache.isCached(unitID: "haven.unit.test"))
    }

    func testValidationSucceedsWithEntrypointCommand() throws {
        let archive = try makeFixtureFile()
        let mockDl = MockDownloadClient()
        let remoteURL = URL(string: "https://example.com/app.zip")!
        mockDl.responses[remoteURL] = archive

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDl,
            extractor: NamedExecutableExtractor(executableName: "my-server"),
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip,
            entrypointCommand: "my-server"
        )

        let result = try installer.install(descriptor: descriptor)
        XCTAssertFalse(result.wasCached)
        XCTAssertTrue(cache.isCached(unitID: "haven.unit.test"))
    }

    func testValidationFailsWithWrongEntrypointCommand() throws {
        let archive = try makeFixtureFile()
        let mockDl = MockDownloadClient()
        let remoteURL = URL(string: "https://example.com/app.zip")!
        mockDl.responses[remoteURL] = archive

        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDl,
            extractor: NamedExecutableExtractor(executableName: "actual-server"),
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip,
            entrypointCommand: "wrong-name"
        )

        XCTAssertThrowsError(try installer.install(descriptor: descriptor)) { error in
            guard case .executableNotFound = error as? ArtifactInstallerError else {
                XCTFail("Expected executableNotFound, got \(error)")
                return
            }
        }
    }
}

// MARK: - ArtifactCache Staging Tests

final class ArtifactCacheStagingTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-staging-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testPrepareStagingDirectoryCreatesInstallingDir() throws {
        let cache = ArtifactCache(installedRoot: tempDir)
        let dir = try cache.prepareStagingDirectory(for: "haven.unit.test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertTrue(dir.lastPathComponent.hasSuffix(".installing"))
    }

    func testPromoteStagingToFinal() throws {
        let cache = ArtifactCache(installedRoot: tempDir)
        let staging = try cache.prepareStagingDirectory(for: "haven.unit.test")
        // Add content to staging
        try Data("content".utf8).write(to: staging.appendingPathComponent("app"))

        try cache.promoteStagingDirectory(for: "haven.unit.test")

        // Final directory should exist with content
        let final_ = cache.installDirectory(for: "haven.unit.test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: final_.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: final_.appendingPathComponent("app").path
            )
        )
        // Staging should be gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func testPromoteReplacesFinalDirectory() throws {
        let cache = ArtifactCache(installedRoot: tempDir)

        // Create a final directory with old content
        let finalDir = cache.installDirectory(for: "haven.unit.test")
        try FileManager.default.createDirectory(at: finalDir, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: finalDir.appendingPathComponent("old-file"))

        // Create staging with new content
        let staging = try cache.prepareStagingDirectory(for: "haven.unit.test")
        try Data("new".utf8).write(to: staging.appendingPathComponent("new-file"))

        try cache.promoteStagingDirectory(for: "haven.unit.test")

        // New content should be present, old should be gone
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: finalDir.appendingPathComponent("new-file").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: finalDir.appendingPathComponent("old-file").path
            )
        )
    }

    func testCleanStaleStagingDirectories() throws {
        let cache = ArtifactCache(installedRoot: tempDir)

        // Create some stale staging dirs
        let stale1 = tempDir.appendingPathComponent("unit-a.installing")
        let stale2 = tempDir.appendingPathComponent("unit-b.installing")
        let legitimate = tempDir.appendingPathComponent("unit-c") // not a staging dir
        try FileManager.default.createDirectory(at: stale1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stale2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legitimate, withIntermediateDirectories: true)

        try cache.cleanStaleStagingDirectories()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legitimate.path))
    }

    func testPrepareStagingCleansOldStaging() throws {
        let cache = ArtifactCache(installedRoot: tempDir)

        // Create an old staging directory with content
        let oldStaging = cache.stagingDirectory(for: "haven.unit.test")
        try FileManager.default.createDirectory(at: oldStaging, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: oldStaging.appendingPathComponent("old"))

        // Prepare new staging — should replace old
        let newStaging = try cache.prepareStagingDirectory(for: "haven.unit.test")

        XCTAssertEqual(oldStaging.path, newStaging.path)
        // Old content should be gone
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: newStaging.appendingPathComponent("old").path
            )
        )
        // Directory should exist and be empty
        let contents = try FileManager.default.contentsOfDirectory(atPath: newStaging.path)
        XCTAssertTrue(contents.isEmpty)
    }
}

// MARK: - Entrypoint Path Validation Tests

final class ArtifactInstallerEntrypointPathTests: XCTestCase {

    private var tempDir: URL!
    private var installedDir: URL!
    private var downloadsDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-entrypoint-test-\(UUID().uuidString)")
        installedDir = tempDir.appendingPathComponent("Installed")
        downloadsDir = tempDir.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: installedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeFixtureFile() throws -> URL {
        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let file = fixtureDir.appendingPathComponent("app.zip")
        try Data("fake-archive".utf8).write(to: file)
        return file
    }

    private func makeInstallerWith(remoteURL: URL, archive: URL, extractor: some ArchiveExtractor) -> (ArtifactInstaller, MockDownloadClient) {
        let mockDl = MockDownloadClient()
        mockDl.responses[remoteURL] = archive
        let cache = ArtifactCache(installedRoot: installedDir)
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDl,
            extractor: extractor,
            downloadsDirectory: downloadsDir
        )
        return (installer, mockDl)
    }

    func testDotSlashBinaryEntrypointSucceeds() throws {
        let archive = try makeFixtureFile()
        let remoteURL = URL(string: "https://example.com/app.zip")!
        let (installer, _) = makeInstallerWith(
            remoteURL: remoteURL, archive: archive,
            extractor: NamedExecutableExtractor(executableName: "my-server")
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip,
            entrypointCommand: "./my-server"
        )

        let result = try installer.install(descriptor: descriptor)
        XCTAssertFalse(result.wasCached)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.installDirectory.appendingPathComponent("my-server").path
            )
        )
    }

    func testDotSlashNestedPathEntrypointSucceeds() throws {
        // Extractor that creates bin/my-server inside the directory
        let ext = NestedExecutableExtractor(relativePath: "bin/my-server")
        let archive = try makeFixtureFile()
        let remoteURL = URL(string: "https://example.com/app.zip")!
        let (installer, _) = makeInstallerWith(
            remoteURL: remoteURL, archive: archive, extractor: ext
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip,
            entrypointCommand: "./bin/my-server"
        )

        let result = try installer.install(descriptor: descriptor)
        XCTAssertFalse(result.wasCached)
    }

    func testBareNameEntrypointSucceeds() throws {
        // bare "my-server" (no ./) should also work — treated as relative to root
        let archive = try makeFixtureFile()
        let remoteURL = URL(string: "https://example.com/app.zip")!
        let (installer, _) = makeInstallerWith(
            remoteURL: remoteURL, archive: archive,
            extractor: NamedExecutableExtractor(executableName: "my-server")
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip,
            entrypointCommand: "my-server"
        )

        let result = try installer.install(descriptor: descriptor)
        XCTAssertFalse(result.wasCached)
    }

    func testAbsolutePathEntrypointIsRejected() throws {
        let archive = try makeFixtureFile()
        let remoteURL = URL(string: "https://example.com/app.zip")!
        let (installer, _) = makeInstallerWith(
            remoteURL: remoteURL, archive: archive,
            extractor: NamedExecutableExtractor(executableName: "my-server")
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip,
            entrypointCommand: "/usr/bin/my-server"
        )

        XCTAssertThrowsError(try installer.install(descriptor: descriptor)) { error in
            guard case .invalidEntrypointPath(let unitID, let path) = error as? ArtifactInstallerError else {
                XCTFail("Expected invalidEntrypointPath, got \(error)")
                return
            }
            XCTAssertEqual(unitID, "haven.unit.test")
            XCTAssertEqual(path, "/usr/bin/my-server")
        }
    }

    func testPathTraversalEntrypointIsRejected() throws {
        let archive = try makeFixtureFile()
        let remoteURL = URL(string: "https://example.com/app.zip")!
        let (installer, _) = makeInstallerWith(
            remoteURL: remoteURL, archive: archive,
            extractor: NamedExecutableExtractor(executableName: "my-server")
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip,
            entrypointCommand: "../../../etc/passwd"
        )

        XCTAssertThrowsError(try installer.install(descriptor: descriptor)) { error in
            guard case .invalidEntrypointPath = error as? ArtifactInstallerError else {
                XCTFail("Expected invalidEntrypointPath, got \(error)")
                return
            }
        }
    }

    func testEmptyDotSlashEntrypointIsRejected() throws {
        let archive = try makeFixtureFile()
        let remoteURL = URL(string: "https://example.com/app.zip")!
        let (installer, _) = makeInstallerWith(
            remoteURL: remoteURL, archive: archive,
            extractor: NamedExecutableExtractor(executableName: "my-server")
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip,
            entrypointCommand: "./"
        )

        XCTAssertThrowsError(try installer.install(descriptor: descriptor)) { error in
            guard case .invalidEntrypointPath = error as? ArtifactInstallerError else {
                XCTFail("Expected invalidEntrypointPath, got \(error)")
                return
            }
        }
    }
}

// MARK: - Broken Cache Recovery Tests

final class ArtifactInstallerBrokenCacheTests: XCTestCase {

    private var tempDir: URL!
    private var installedDir: URL!
    private var downloadsDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-broken-cache-test-\(UUID().uuidString)")
        installedDir = tempDir.appendingPathComponent("Installed")
        downloadsDir = tempDir.appendingPathComponent("Downloads")
        try? FileManager.default.createDirectory(at: installedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeFixtureFile() throws -> URL {
        let fixtureDir = tempDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(at: fixtureDir, withIntermediateDirectories: true)
        let file = fixtureDir.appendingPathComponent("app.zip")
        try Data("fake-archive".utf8).write(to: file)
        return file
    }

    func testBrokenCacheTriggersReinstall() throws {
        let archive = try makeFixtureFile()

        // Pre-populate the cache with a non-executable file (broken)
        let unitDir = installedDir.appendingPathComponent("haven.unit.test")
        try FileManager.default.createDirectory(at: unitDir, withIntermediateDirectories: true)
        try Data("not-executable".utf8).write(to: unitDir.appendingPathComponent("data.txt"))

        let cache = ArtifactCache(installedRoot: installedDir)
        XCTAssertTrue(cache.isCached(unitID: "haven.unit.test")) // non-empty → "cached"

        let remoteURL = URL(string: "https://example.com/app.zip")!
        let mockDl = MockDownloadClient()
        mockDl.responses[remoteURL] = archive

        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDl,
            extractor: NamedExecutableExtractor(executableName: "my-app"),
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip
        )

        let result = try installer.install(descriptor: descriptor)

        // Should NOT be a cache hit — broken cache was detected and replaced
        XCTAssertFalse(result.wasCached)
        // New executable should be present
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.installDirectory.appendingPathComponent("my-app").path
            )
        )
        // Download should have been called
        XCTAssertEqual(mockDl.downloadedURLs, [remoteURL])
    }

    func testBrokenCacheWithEntrypointTriggersReinstall() throws {
        let archive = try makeFixtureFile()

        // Pre-populate with wrong executable name
        let unitDir = installedDir.appendingPathComponent("haven.unit.test")
        try FileManager.default.createDirectory(at: unitDir, withIntermediateDirectories: true)
        let wrongExec = unitDir.appendingPathComponent("wrong-name")
        try Data("#!/bin/sh\necho hi".utf8).write(to: wrongExec)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: wrongExec.path
        )

        let cache = ArtifactCache(installedRoot: installedDir)
        XCTAssertTrue(cache.isCached(unitID: "haven.unit.test"))

        let remoteURL = URL(string: "https://example.com/app.zip")!
        let mockDl = MockDownloadClient()
        mockDl.responses[remoteURL] = archive

        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDl,
            extractor: NamedExecutableExtractor(executableName: "my-server"),
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(remoteURL),
            format: .zip,
            entrypointCommand: "./my-server"
        )

        let result = try installer.install(descriptor: descriptor)

        // Cache was broken (wrong executable), so should reinstall
        XCTAssertFalse(result.wasCached)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.installDirectory.appendingPathComponent("my-server").path
            )
        )
    }

    func testValidCacheStillReturnsCacheHit() throws {
        // Pre-populate with a valid executable
        let unitDir = installedDir.appendingPathComponent("haven.unit.test")
        try FileManager.default.createDirectory(at: unitDir, withIntermediateDirectories: true)
        let exec = unitDir.appendingPathComponent("my-app")
        try Data("#!/bin/sh\necho hi".utf8).write(to: exec)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: exec.path
        )

        let cache = ArtifactCache(installedRoot: installedDir)
        let mockDl = MockDownloadClient()
        let installer = ArtifactInstaller(
            cache: cache,
            downloadClient: mockDl,
            extractor: MockArchiveExtractor(),
            downloadsDirectory: downloadsDir
        )

        let descriptor = ArtifactDescriptor(
            unitID: "haven.unit.test",
            source: .remote(URL(string: "https://example.com/app.zip")!),
            format: .zip
        )

        let result = try installer.install(descriptor: descriptor)

        // Valid cache — should be a cache hit, no download
        XCTAssertTrue(result.wasCached)
        XCTAssertTrue(mockDl.downloadedURLs.isEmpty)
    }
}

// MARK: - Test-only helper: Nested executable extractor

/// Simulates an archive that extracts an executable at a nested path.
private final class NestedExecutableExtractor: ArchiveExtractor, @unchecked Sendable {
    let relativePath: String

    init(relativePath: String) {
        self.relativePath = relativePath
    }

    func extract(archiveURL: URL, to destinationDirectory: URL, format: ArtifactFormat) throws {
        let fullPath = destinationDirectory.appendingPathComponent(relativePath)
        let parentDir = fullPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho hello".utf8).write(to: fullPath)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: fullPath.path
        )
    }
}
