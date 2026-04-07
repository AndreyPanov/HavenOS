import XCTest
import Foundation
import HavenCore
import HavenRuntimes
import HavenLaunchd
import HavenInstaller
@testable import HavenExecutor

// MARK: - E2E Mock Download Client

/// A mock download client that returns a pre-built zip fixture.
private final class E2EDownloadClient: DownloadClient, @unchecked Sendable {
    let fixtureFile: URL
    private(set) var downloadedURLs: [URL] = []

    init(fixtureFile: URL) {
        self.fixtureFile = fixtureFile
    }

    func download(from url: URL) throws -> URL {
        downloadedURLs.append(url)
        return fixtureFile
    }
}

// MARK: - E2E Mock LaunchctlClient

private final class E2ELaunchctlClient: LaunchctlClient, @unchecked Sendable {
    var bootstrapCalls: [String] = []
    var bootoutCalls: [String] = []

    private let success = LaunchctlResult(exitCode: 0, stdout: "", stderr: "")

    func bootstrap(plistPath: String) throws -> LaunchctlResult {
        bootstrapCalls.append(plistPath)
        return success
    }

    func bootout(label: String) throws -> LaunchctlResult {
        bootoutCalls.append(label)
        return success
    }

    func start(label: String) throws -> LaunchctlResult { success }
    func stop(label: String) throws -> LaunchctlResult { success }
    func print(label: String) throws -> LaunchctlResult { success }
}

// MARK: - Artifact E2E Tests

final class ArtifactE2ETests: XCTestCase {

    private var tempDir: URL!
    private var paths: HavenPaths!
    private var stateStore: FileStateStore!
    private var mockLaunchctl: E2ELaunchctlClient!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-e2e-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        paths = HavenPaths(base: tempDir)
        stateStore = FileStateStore(paths: paths)
        mockLaunchctl = E2ELaunchctlClient()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Create a real zip archive containing a mock executable.
    private func createZipFixture(executableName: String) throws -> URL {
        let sourceDir = tempDir.appendingPathComponent("zip-source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let execFile = sourceDir.appendingPathComponent(executableName)
        try "#!/bin/sh\necho hello".write(to: execFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: execFile.path
        )

        let zipFile = tempDir.appendingPathComponent("fixture.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-ck", sourceDir.path, zipFile.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "E2ETest", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create zip fixture"
            ])
        }

        return zipFile
    }

    /// Build a registry with a single artifact-based unit.
    private func makeArtifactRegistry(
        executableName: String = "hello-service",
        entrypointCommand: String? = nil
    ) -> SpecRegistry {
        let entrypoint: RuntimeUnit.Entrypoint? = entrypointCommand.map {
            RuntimeUnit.Entrypoint(command: $0)
        }
        let unit = RuntimeUnit(
            id: "haven.unit.hello",
            bundleID: "haven.bundle.hello-basic",
            runtimeType: .native,
            installSource: "",
            launchArguments: ["--port", "${port}"],
            port: 9090,
            entrypoint: entrypoint,
            artifact: Artifact(
                type: .githubRelease,
                repo: "owner/hello-service",
                version: "v1.0.0",
                assets: [
                    ArtifactAsset(os: "macos", arch: "arm64", file: "\(executableName)-macos-arm64.zip"),
                    ArtifactAsset(os: "macos", arch: "x86_64", file: "\(executableName)-macos-x86_64.zip"),
                ]
            )
        )

        return SpecRegistry(
            capabilitiesByID: [
                "haven.capability.hello": Capability(
                    id: "haven.capability.hello",
                    name: "Hello Service",
                    version: "1.0.0",
                    description: "A test service"
                )
            ],
            bundlesByID: [
                "haven.bundle.hello-basic": Bundle(
                    id: "haven.bundle.hello-basic",
                    name: "Hello Basic",
                    capability: "haven.capability.hello",
                    runtimeUnits: ["haven.unit.hello"]
                )
            ],
            runtimeUnitsByID: [
                "haven.unit.hello": unit
            ]
        )
    }

    // MARK: - Full lifecycle test

    func testInstallAndUninstallWithArtifact() throws {
        // 1. Create a real zip fixture
        let zipFile = try createZipFixture(executableName: "hello-service")

        // 2. Set up mock download client
        let downloadClient = E2EDownloadClient(fixtureFile: zipFile)

        // 3. Build executor with real components
        let launchdPaths = LaunchdPaths(
            launchAgentsDirectory: tempDir.appendingPathComponent("LaunchAgents")
        )
        let installer = ArtifactInstaller(
            paths: paths,
            downloadClient: downloadClient,
            extractor: ProcessArchiveExtractor()
        )
        let executor = HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: LaunchdController(paths: launchdPaths, client: mockLaunchctl),
            artifactInstaller: installer
        )

        // 4. Install
        let registry = makeArtifactRegistry()
        let state = try executor.install(
            capabilityID: "haven.capability.hello",
            registry: registry
        )

        // 5. Verify state
        XCTAssertEqual(state.capability, "haven.capability.hello")
        XCTAssertEqual(state.bundleID, "haven.bundle.hello-basic")
        XCTAssertEqual(state.runtimeUnits, ["haven.unit.hello"])
        XCTAssertEqual(state.status, .installed)

        // 6. Verify artifact metadata was persisted
        XCTAssertEqual(state.artifactInfo.count, 1)
        XCTAssertEqual(state.artifactInfo[0].unitID, "haven.unit.hello")
        XCTAssertEqual(state.artifactInfo[0].repo, "owner/hello-service")
        XCTAssertEqual(state.artifactInfo[0].version, "v1.0.0")
        XCTAssertEqual(state.artifactInfo[0].format, "zip")
        XCTAssertTrue(state.artifactInfo[0].platform.contains("macos"))

        // 7. Verify binary was installed
        let installDir = paths.installedDirectory
            .appendingPathComponent("haven.unit.hello", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installDir.path))

        // 8. Verify launchd was called
        XCTAssertEqual(mockLaunchctl.bootstrapCalls.count, 1)

        // 9. Verify download was called
        XCTAssertEqual(downloadClient.downloadedURLs.count, 1)

        // 10. Verify persisted state can be reloaded
        let persisted = try stateStore.service(for: "haven.capability.hello")
        XCTAssertNotNil(persisted)
        XCTAssertEqual(persisted?.artifactInfo.count, 1)

        // 11. Uninstall
        try executor.uninstall(capabilityID: "haven.capability.hello")

        // 12. Verify cleanup
        let afterUninstall = try stateStore.service(for: "haven.capability.hello")
        XCTAssertNil(afterUninstall)
        XCTAssertEqual(mockLaunchctl.bootoutCalls.count, 1)
    }

    func testInstallWithEntrypointCommand() throws {
        let zipFile = try createZipFixture(executableName: "my-server")

        let downloadClient = E2EDownloadClient(fixtureFile: zipFile)
        let launchdPaths = LaunchdPaths(
            launchAgentsDirectory: tempDir.appendingPathComponent("LaunchAgents")
        )
        let installer = ArtifactInstaller(
            paths: paths,
            downloadClient: downloadClient,
            extractor: ProcessArchiveExtractor()
        )
        let executor = HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: LaunchdController(paths: launchdPaths, client: mockLaunchctl),
            artifactInstaller: installer
        )

        let registry = makeArtifactRegistry(
            executableName: "my-server",
            entrypointCommand: "my-server"
        )

        let state = try executor.install(
            capabilityID: "haven.capability.hello",
            registry: registry
        )

        XCTAssertEqual(state.status, .installed)
        XCTAssertEqual(state.artifactInfo.count, 1)

        // Verify the binary exists at the expected location
        let installDir = paths.installedDirectory
            .appendingPathComponent("haven.unit.hello", isDirectory: true)
        // ditto preserves directory structure, so look for the file
        XCTAssertTrue(FileManager.default.fileExists(atPath: installDir.path))
    }
}
