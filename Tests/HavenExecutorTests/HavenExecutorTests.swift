import XCTest
import Foundation
import HavenCore
import HavenRuntimes
import HavenLaunchd
import HavenInstaller
@testable import HavenExecutor

// MARK: - MockLaunchctlClient

final class MockLaunchctlClient: LaunchctlClient, @unchecked Sendable {

    struct Call: Equatable {
        let method: String
        let arguments: [String]
    }

    var calls: [Call] = []

    /// Canned results keyed by method name. Falls back to a success result.
    var results: [String: LaunchctlResult] = [:]

    /// If set, the next call to this method will throw this error.
    var throwOnMethod: [String: Error] = [:]

    private let defaultSuccess = LaunchctlResult(exitCode: 0, stdout: "", stderr: "")

    func bootstrap(plistPath: String) throws -> LaunchctlResult {
        try record("bootstrap", arguments: [plistPath])
    }

    func bootout(label: String) throws -> LaunchctlResult {
        try record("bootout", arguments: [label])
    }

    func start(label: String) throws -> LaunchctlResult {
        try record("start", arguments: [label])
    }

    func stop(label: String) throws -> LaunchctlResult {
        try record("stop", arguments: [label])
    }

    func print(label: String) throws -> LaunchctlResult {
        try record("print", arguments: [label])
    }

    private func record(_ method: String, arguments: [String]) throws -> LaunchctlResult {
        calls.append(Call(method: method, arguments: arguments))
        if let error = throwOnMethod[method] {
            throw error
        }
        return results[method] ?? defaultSuccess
    }
}

// MARK: - Shared Helpers

private func makeStandardRegistry() -> SpecRegistry {
    SpecRegistry(
        capabilitiesByID: [
            "haven.capability.test-library": .testLibraryExample
        ],
        bundlesByID: [
            "haven.bundle.test-library-basic": .testLibraryBasicExample
        ],
        runtimeUnitsByID: [
            "haven.unit.test-db": .testDBExample,
            "haven.unit.test-worker": .testWorkerExample,
            "haven.unit.test-web": .testWebExample,
        ]
    )
}

/// Creates a registry with installSource paths pointing to real files in the given directory.
private func makeLocalArtifactRegistry(artifactDir: URL) -> SpecRegistry {
    let dbPath = artifactDir.appendingPathComponent("test-db").path
    let workerPath = artifactDir.appendingPathComponent("test-worker").path
    let webPath = artifactDir.appendingPathComponent("test-web").path

    return SpecRegistry(
        capabilitiesByID: [
            "haven.capability.test-library": .testLibraryExample
        ],
        bundlesByID: [
            "haven.bundle.test-library-basic": .testLibraryBasicExample
        ],
        runtimeUnitsByID: [
            "haven.unit.test-db": RuntimeUnit(
                id: "haven.unit.test-db",
                bundleID: "haven.bundle.test-library-basic",
                runtimeType: .native,
                installSource: dbPath,
                launchArguments: [dbPath, "--datadir", "${data_dir}/db"],
                healthcheck: Healthcheck(type: .tcp, target: "localhost:5432", intervalSeconds: 10, retries: 3),
                environment: ["DB_DATA": "${data_path}"]
            ),
            "haven.unit.test-worker": RuntimeUnit(
                id: "haven.unit.test-worker",
                bundleID: "haven.bundle.test-library-basic",
                runtimeType: .native,
                installSource: workerPath,
                launchArguments: [workerPath, "--config", "${config_dir}/worker.toml"],
                dependsOn: ["haven.unit.test-db"],
                environment: ["WORKER_DATA": "${data_path}", "WORKER_LOGS": "${logs_dir}"]
            ),
            "haven.unit.test-web": RuntimeUnit(
                id: "haven.unit.test-web",
                bundleID: "haven.bundle.test-library-basic",
                runtimeType: .native,
                installSource: webPath,
                launchArguments: [webPath, "--port", "${port}"],
                healthcheck: Healthcheck(type: .http, target: "http://localhost:${port}/health", intervalSeconds: 15, retries: 3),
                dependsOn: ["haven.unit.test-worker"],
                port: 8080,
                environment: ["WEB_PORT": "${port}", "WEB_DATA": "${data_path}", "WEB_LOGS": "${logs_dir}"]
            ),
        ]
    )
}

/// Creates a registry with a single Python runtime unit (unsupported in executor MVP).
private func makePythonRegistry() -> SpecRegistry {
    SpecRegistry(
        capabilitiesByID: [
            "haven.capability.python-app": Capability(
                id: "haven.capability.python-app",
                name: "Python App",
                version: "1.0.0",
                summary: "A Python-based service"
            )
        ],
        bundlesByID: [
            "haven.bundle.python-basic": Bundle(
                id: "haven.bundle.python-basic",
                name: "Python Basic",
                capabilityID: "haven.capability.python-app",
                runtimeUnitIDs: ["haven.unit.python-server"]
            )
        ],
        runtimeUnitsByID: [
            "haven.unit.python-server": RuntimeUnit(
                id: "haven.unit.python-server",
                bundleID: "haven.bundle.python-basic",
                runtimeType: .python,
                installSource: "/opt/haven/python/app.py",
                launchArguments: ["python3", "/opt/haven/python/app.py"]
            )
        ]
    )
}

private let testCapabilityID = "haven.capability.test-library"
private let testSettings: [String: String] = ["data_path": "/srv/data"]

/// Creates dummy executable files in the given directory.
private func createDummyExecutables(in dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let filenames = ["test-db", "test-worker", "test-web"]
    for name in filenames {
        let path = dir.appendingPathComponent(name)
        try "#!/bin/sh\necho hello".write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: path.path
        )
    }
}

// MARK: - Install Tests (without artifact installer)

final class HavenExecutorInstallTests: XCTestCase {

    private var tempDir: URL!
    private var mock: MockLaunchctlClient!
    private var executor: HavenExecutor!
    private var stateStore: FileStateStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-executor-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        mock = MockLaunchctlClient()
        let paths = HavenPaths(base: tempDir)
        let launchdPaths = LaunchdPaths(
            launchAgentsDirectory: tempDir.appendingPathComponent("LaunchAgents")
        )
        stateStore = FileStateStore(paths: paths)
        executor = HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: LaunchdController(paths: launchdPaths, client: mock)
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInstallCreatesStateEntry() throws {
        let state = try executor.install(
            capabilityID: testCapabilityID,
            registry: makeStandardRegistry(),
            settings: testSettings
        )
        XCTAssertEqual(state.capabilityID, testCapabilityID)

        let persisted = try stateStore.service(for: testCapabilityID)
        XCTAssertNotNil(persisted)
        XCTAssertEqual(persisted?.capabilityID, testCapabilityID)
    }

    func testInstallPersistsCorrectUnitIDs() throws {
        let state = try executor.install(
            capabilityID: testCapabilityID,
            registry: makeStandardRegistry(),
            settings: testSettings
        )
        // Units are in topological order: db first, then worker, then web
        XCTAssertEqual(state.runtimeUnitIDs, [
            "haven.unit.test-db",
            "haven.unit.test-worker",
            "haven.unit.test-web",
        ])
    }

    func testInstallCreatesServiceDirectories() throws {
        _ = try executor.install(
            capabilityID: testCapabilityID,
            registry: makeStandardRegistry(),
            settings: testSettings
        )

        let paths = HavenPaths(base: tempDir)
        let layout = paths.serviceLayout(for: testCapabilityID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.data.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.config.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.logs.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.run.path))
    }

    func testInstallCallsBootstrapForEachUnit() throws {
        _ = try executor.install(
            capabilityID: testCapabilityID,
            registry: makeStandardRegistry(),
            settings: testSettings
        )

        let bootstrapCalls = mock.calls.filter { $0.method == "bootstrap" }
        XCTAssertEqual(bootstrapCalls.count, 3)
    }

    func testInstallSetsStatusToInstalled() throws {
        let state = try executor.install(
            capabilityID: testCapabilityID,
            registry: makeStandardRegistry(),
            settings: testSettings
        )
        XCTAssertEqual(state.status, .installed)
    }

    func testInstallPersistsPortAssignments() throws {
        let state = try executor.install(
            capabilityID: testCapabilityID,
            registry: makeStandardRegistry(),
            settings: testSettings
        )
        // test-web has port 8080
        let webPort = state.portAssignments.first(where: { $0.unitID == "haven.unit.test-web" })
        XCTAssertEqual(webPort?.port, 8080)
    }

    func testInstallPersistsResolvedSettings() throws {
        let state = try executor.install(
            capabilityID: testCapabilityID,
            registry: makeStandardRegistry(),
            settings: testSettings
        )
        XCTAssertEqual(state.resolvedSettings["data_path"], "/srv/data")
    }

    func testInstallAlreadyInstalledThrows() throws {
        _ = try executor.install(
            capabilityID: testCapabilityID,
            registry: makeStandardRegistry(),
            settings: testSettings
        )

        XCTAssertThrowsError(
            try executor.install(
                capabilityID: testCapabilityID,
                registry: makeStandardRegistry(),
                settings: testSettings
            )
        ) { error in
            guard case .alreadyInstalled(let capID) = error as? ExecutorError else {
                XCTFail("Expected alreadyInstalled, got \(error)")
                return
            }
            XCTAssertEqual(capID, testCapabilityID)
        }
    }

    func testInstallInvalidCapabilityThrows() {
        XCTAssertThrowsError(
            try executor.install(
                capabilityID: "nonexistent.capability",
                registry: makeStandardRegistry(),
                settings: [:]
            )
        ) { error in
            guard case .planningFailed = error as? ExecutorError else {
                XCTFail("Expected planningFailed, got \(error)")
                return
            }
        }
    }
}

// MARK: - Artifact-Backed Install Tests

final class HavenExecutorArtifactTests: XCTestCase {

    private var tempDir: URL!
    private var artifactDir: URL!
    private var mock: MockLaunchctlClient!
    private var executor: HavenExecutor!
    private var stateStore: FileStateStore!
    private var paths: HavenPaths!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-artifact-test-\(UUID().uuidString)")
        artifactDir = tempDir.appendingPathComponent("source-artifacts")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        mock = MockLaunchctlClient()
        paths = HavenPaths(base: tempDir)
        let launchdPaths = LaunchdPaths(
            launchAgentsDirectory: tempDir.appendingPathComponent("LaunchAgents")
        )
        stateStore = FileStateStore(paths: paths)
        let installer = ArtifactInstaller(paths: paths)
        executor = HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: LaunchdController(paths: launchdPaths, client: mock),
            artifactInstaller: installer
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInstallWithArtifactsCopiesExecutables() throws {
        try createDummyExecutables(in: artifactDir)
        let registry = makeLocalArtifactRegistry(artifactDir: artifactDir)

        let state = try executor.install(
            capabilityID: testCapabilityID,
            registry: registry,
            settings: testSettings
        )

        XCTAssertEqual(state.status, .installed)
        XCTAssertEqual(state.runtimeUnitIDs.count, 3)

        // Verify artifacts were installed to Installed/<unit-id>/
        for unitID in state.runtimeUnitIDs {
            let installDir = paths.installedDirectory.appendingPathComponent(unitID)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: installDir.path),
                "Installed directory should exist for \(unitID)"
            )
            let contents = try FileManager.default.contentsOfDirectory(atPath: installDir.path)
            XCTAssertFalse(contents.isEmpty, "Install directory should not be empty for \(unitID)")
        }
    }

    func testInstallWithArtifactsUsesDeterministicPaths() throws {
        try createDummyExecutables(in: artifactDir)
        let registry = makeLocalArtifactRegistry(artifactDir: artifactDir)

        _ = try executor.install(
            capabilityID: testCapabilityID,
            registry: registry,
            settings: testSettings
        )

        // Verify deterministic paths: <base>/Installed/<unit-id>/<filename>
        let dbInstalled = paths.installedDirectory
            .appendingPathComponent("haven.unit.test-db")
            .appendingPathComponent("test-db")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbInstalled.path))

        let webInstalled = paths.installedDirectory
            .appendingPathComponent("haven.unit.test-web")
            .appendingPathComponent("test-web")
        XCTAssertTrue(FileManager.default.fileExists(atPath: webInstalled.path))
    }

    func testInstallWithMissingArtifactThrows() {
        // Don't create the artifact files — they should be missing
        let registry = makeLocalArtifactRegistry(artifactDir: artifactDir)

        XCTAssertThrowsError(
            try executor.install(
                capabilityID: testCapabilityID,
                registry: registry,
                settings: testSettings
            )
        ) { error in
            guard case .artifactInstallFailed(let capID, let unitID, _) = error as? ExecutorError else {
                XCTFail("Expected artifactInstallFailed, got \(error)")
                return
            }
            XCTAssertEqual(capID, testCapabilityID)
            // First unit (topological order) is test-db
            XCTAssertEqual(unitID, "haven.unit.test-db")
        }
    }

    func testUninstallRemovesArtifacts() throws {
        try createDummyExecutables(in: artifactDir)
        let registry = makeLocalArtifactRegistry(artifactDir: artifactDir)

        _ = try executor.install(
            capabilityID: testCapabilityID,
            registry: registry,
            settings: testSettings
        )

        // Verify artifacts exist
        let dbInstallDir = paths.installedDirectory.appendingPathComponent("haven.unit.test-db")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbInstallDir.path))

        try executor.uninstall(capabilityID: testCapabilityID)

        // Verify artifacts removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbInstallDir.path))
    }

    func testInstallWithArtifactsCallsBootstrap() throws {
        try createDummyExecutables(in: artifactDir)
        let registry = makeLocalArtifactRegistry(artifactDir: artifactDir)

        _ = try executor.install(
            capabilityID: testCapabilityID,
            registry: registry,
            settings: testSettings
        )

        let bootstrapCalls = mock.calls.filter { $0.method == "bootstrap" }
        XCTAssertEqual(bootstrapCalls.count, 3)
    }

    func testFullLifecycleWithArtifacts() throws {
        try createDummyExecutables(in: artifactDir)
        let registry = makeLocalArtifactRegistry(artifactDir: artifactDir)

        // Install
        let state = try executor.install(
            capabilityID: testCapabilityID,
            registry: registry,
            settings: testSettings
        )
        XCTAssertEqual(state.status, .installed)

        // Start
        try executor.start(capabilityID: testCapabilityID)
        let afterStart = try stateStore.service(for: testCapabilityID)
        XCTAssertEqual(afterStart?.status, .running)

        // Stop
        try executor.stop(capabilityID: testCapabilityID)
        let afterStop = try stateStore.service(for: testCapabilityID)
        XCTAssertEqual(afterStop?.status, .stopped)

        // Uninstall
        try executor.uninstall(capabilityID: testCapabilityID)
        let afterUninstall = try stateStore.service(for: testCapabilityID)
        XCTAssertNil(afterUninstall)

        // Verify artifacts cleaned up
        for unitID in state.runtimeUnitIDs {
            let installDir = paths.installedDirectory.appendingPathComponent(unitID)
            XCTAssertFalse(FileManager.default.fileExists(atPath: installDir.path))
        }
    }
}

// MARK: - Python Runtime Rejection Tests

final class HavenExecutorPythonTests: XCTestCase {

    private var tempDir: URL!
    private var mock: MockLaunchctlClient!
    private var executor: HavenExecutor!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-python-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        mock = MockLaunchctlClient()
        let paths = HavenPaths(base: tempDir)
        let launchdPaths = LaunchdPaths(
            launchAgentsDirectory: tempDir.appendingPathComponent("LaunchAgents")
        )
        let stateStore = FileStateStore(paths: paths)
        executor = HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: LaunchdController(paths: launchdPaths, client: mock)
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testPythonRuntimeRejectsCleanly() {
        let registry = makePythonRegistry()

        XCTAssertThrowsError(
            try executor.install(
                capabilityID: "haven.capability.python-app",
                registry: registry,
                settings: [:]
            )
        ) { error in
            guard case .unsupportedRuntime(let capID, let unitID, let detail) = error as? ExecutorError else {
                XCTFail("Expected unsupportedRuntime, got \(error)")
                return
            }
            XCTAssertEqual(capID, "haven.capability.python-app")
            XCTAssertEqual(unitID, "haven.unit.python-server")
            // Verify no tooling leaks in the error detail
            let forbidden = ["pip", "python", "brew", "PATH", "venv"]
            for word in forbidden {
                XCTAssertFalse(
                    detail.contains(word),
                    "Error detail should not contain '\(word)': \(detail)"
                )
            }
        }
    }

    func testPythonRuntimeDoesNotCreateState() {
        let registry = makePythonRegistry()
        let stateStore = FileStateStore(paths: HavenPaths(base: tempDir))

        _ = try? executor.install(
            capabilityID: "haven.capability.python-app",
            registry: registry,
            settings: [:]
        )

        let persisted = try? stateStore.service(for: "haven.capability.python-app")
        XCTAssertNil(persisted, "No state should be persisted when install fails")
    }

    func testPythonRuntimeDoesNotCallLaunchd() {
        let registry = makePythonRegistry()

        _ = try? executor.install(
            capabilityID: "haven.capability.python-app",
            registry: registry,
            settings: [:]
        )

        XCTAssertTrue(mock.calls.isEmpty, "No launchd calls should be made when install fails early")
    }
}

// MARK: - Uninstall Tests

final class HavenExecutorUninstallTests: XCTestCase {

    private var tempDir: URL!
    private var mock: MockLaunchctlClient!
    private var executor: HavenExecutor!
    private var stateStore: FileStateStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-executor-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        mock = MockLaunchctlClient()
        let paths = HavenPaths(base: tempDir)
        let launchdPaths = LaunchdPaths(
            launchAgentsDirectory: tempDir.appendingPathComponent("LaunchAgents")
        )
        stateStore = FileStateStore(paths: paths)
        executor = HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: LaunchdController(paths: launchdPaths, client: mock)
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func installTestService() throws {
        _ = try executor.install(
            capabilityID: testCapabilityID,
            registry: makeStandardRegistry(),
            settings: testSettings
        )
        mock.calls.removeAll()
    }

    func testUninstallRemovesStateEntry() throws {
        try installTestService()
        try executor.uninstall(capabilityID: testCapabilityID)

        let persisted = try stateStore.service(for: testCapabilityID)
        XCTAssertNil(persisted)
    }

    func testUninstallCallsBootoutForEachUnit() throws {
        try installTestService()
        try executor.uninstall(capabilityID: testCapabilityID)

        let bootoutCalls = mock.calls.filter { $0.method == "bootout" }
        XCTAssertEqual(bootoutCalls.count, 3)
    }

    func testUninstallStopsBeforeUnloading() throws {
        try installTestService()
        try executor.uninstall(capabilityID: testCapabilityID)

        // For each unit: stop then bootout
        // Reverse order: web, worker, db
        // Each unit gets a stop call, then a bootout call
        let stopCalls = mock.calls.filter { $0.method == "stop" }
        let bootoutCalls = mock.calls.filter { $0.method == "bootout" }
        XCTAssertEqual(stopCalls.count, 3)
        XCTAssertEqual(bootoutCalls.count, 3)

        // Verify stop always comes before bootout for same unit
        for (i, call) in mock.calls.enumerated() {
            if call.method == "bootout" {
                // There should be a stop call before this bootout
                let matchingStop = mock.calls[0..<i].contains { c in
                    c.method == "stop"
                }
                XCTAssertTrue(matchingStop, "Expected stop before bootout")
            }
        }
    }

    func testUninstallReversesDependencyOrder() throws {
        try installTestService()
        try executor.uninstall(capabilityID: testCapabilityID)

        // Reverse of install order: web first, then worker, then db
        let bootoutCalls = mock.calls.filter { $0.method == "bootout" }
        XCTAssertEqual(bootoutCalls.count, 3)

        // Bootout arguments contain the service target which includes the label
        // Labels: app.haven.<capID>.<unitID>
        let labels = bootoutCalls.map { $0.arguments[0] }
        XCTAssertTrue(labels[0].contains("test-web"), "Web should be uninstalled first")
        XCTAssertTrue(labels[1].contains("test-worker"), "Worker should be uninstalled second")
        XCTAssertTrue(labels[2].contains("test-db"), "DB should be uninstalled last")
    }

    func testUninstallRemovesServiceDirectory() throws {
        try installTestService()

        let layout = HavenPaths(base: tempDir).serviceLayout(for: testCapabilityID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.serviceRoot.path))

        try executor.uninstall(capabilityID: testCapabilityID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.serviceRoot.path))
    }

    func testUninstallNotInstalledThrows() {
        XCTAssertThrowsError(
            try executor.uninstall(capabilityID: "nonexistent")
        ) { error in
            guard case .notInstalled = error as? ExecutorError else {
                XCTFail("Expected notInstalled, got \(error)")
                return
            }
        }
    }
}

// MARK: - Start/Stop Tests

final class HavenExecutorStartStopTests: XCTestCase {

    private var tempDir: URL!
    private var mock: MockLaunchctlClient!
    private var executor: HavenExecutor!
    private var stateStore: FileStateStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-executor-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        mock = MockLaunchctlClient()
        let paths = HavenPaths(base: tempDir)
        let launchdPaths = LaunchdPaths(
            launchAgentsDirectory: tempDir.appendingPathComponent("LaunchAgents")
        )
        stateStore = FileStateStore(paths: paths)
        executor = HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: LaunchdController(paths: launchdPaths, client: mock)
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func installTestService() throws {
        _ = try executor.install(
            capabilityID: testCapabilityID,
            registry: makeStandardRegistry(),
            settings: testSettings
        )
        mock.calls.removeAll()
    }

    func testStartCallsLaunchdStartForEachUnit() throws {
        try installTestService()
        try executor.start(capabilityID: testCapabilityID)

        let startCalls = mock.calls.filter { $0.method == "start" }
        XCTAssertEqual(startCalls.count, 3)
    }

    func testStartUpdatesStateToRunning() throws {
        try installTestService()
        try executor.start(capabilityID: testCapabilityID)

        let state = try stateStore.service(for: testCapabilityID)
        XCTAssertEqual(state?.status, .running)
    }

    func testStartNotInstalledThrows() {
        XCTAssertThrowsError(
            try executor.start(capabilityID: "nonexistent")
        ) { error in
            guard case .notInstalled = error as? ExecutorError else {
                XCTFail("Expected notInstalled, got \(error)")
                return
            }
        }
    }

    func testStopCallsLaunchdStopInReverseOrder() throws {
        try installTestService()
        try executor.stop(capabilityID: testCapabilityID)

        let stopCalls = mock.calls.filter { $0.method == "stop" }
        XCTAssertEqual(stopCalls.count, 3)

        // Reverse order: web, worker, db
        let labels = stopCalls.map { $0.arguments[0] }
        XCTAssertTrue(labels[0].contains("test-web"))
        XCTAssertTrue(labels[1].contains("test-worker"))
        XCTAssertTrue(labels[2].contains("test-db"))
    }

    func testStopUpdatesStateToStopped() throws {
        try installTestService()
        try executor.stop(capabilityID: testCapabilityID)

        let state = try stateStore.service(for: testCapabilityID)
        XCTAssertEqual(state?.status, .stopped)
    }

    func testStopNotInstalledThrows() {
        XCTAssertThrowsError(
            try executor.stop(capabilityID: "nonexistent")
        ) { error in
            guard case .notInstalled = error as? ExecutorError else {
                XCTFail("Expected notInstalled, got \(error)")
                return
            }
        }
    }
}

// MARK: - Status Tests

final class HavenExecutorStatusTests: XCTestCase {

    private var tempDir: URL!
    private var mock: MockLaunchctlClient!
    private var executor: HavenExecutor!
    private var stateStore: FileStateStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-executor-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        mock = MockLaunchctlClient()
        let paths = HavenPaths(base: tempDir)
        let launchdPaths = LaunchdPaths(
            launchAgentsDirectory: tempDir.appendingPathComponent("LaunchAgents")
        )
        stateStore = FileStateStore(paths: paths)
        executor = HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: LaunchdController(paths: launchdPaths, client: mock)
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func installTestService() throws {
        _ = try executor.install(
            capabilityID: testCapabilityID,
            registry: makeStandardRegistry(),
            settings: testSettings
        )
        mock.calls.removeAll()
    }

    func testStatusReturnsUnitStatuses() throws {
        try installTestService()

        // Configure mock to return "running" status with PID
        mock.results["print"] = LaunchctlResult(
            exitCode: 0,
            stdout: "state = running\npid = 12345\n",
            stderr: ""
        )

        let report = try executor.status(capabilityID: testCapabilityID)
        XCTAssertEqual(report.capabilityID, testCapabilityID)
        XCTAssertEqual(report.unitStatuses.count, 3)
    }

    func testStatusQueriesLaunchdForEachUnit() throws {
        try installTestService()
        _ = try executor.status(capabilityID: testCapabilityID)

        let printCalls = mock.calls.filter { $0.method == "print" }
        XCTAssertEqual(printCalls.count, 3)
    }

    func testStatusNotInstalledThrows() {
        XCTAssertThrowsError(
            try executor.status(capabilityID: "nonexistent")
        ) { error in
            guard case .notInstalled = error as? ExecutorError else {
                XCTFail("Expected notInstalled, got \(error)")
                return
            }
        }
    }
}

// MARK: - End-to-End Lifecycle Test (without artifacts)

final class HavenExecutorEndToEndTests: XCTestCase {

    private var tempDir: URL!
    private var mock: MockLaunchctlClient!
    private var executor: HavenExecutor!
    private var stateStore: FileStateStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-executor-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        mock = MockLaunchctlClient()
        let paths = HavenPaths(base: tempDir)
        let launchdPaths = LaunchdPaths(
            launchAgentsDirectory: tempDir.appendingPathComponent("LaunchAgents")
        )
        stateStore = FileStateStore(paths: paths)
        executor = HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: LaunchdController(paths: launchdPaths, client: mock)
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testFullLifecycle() throws {
        let registry = makeStandardRegistry()

        // 1. Install
        let state = try executor.install(
            capabilityID: testCapabilityID,
            registry: registry,
            settings: testSettings
        )
        XCTAssertEqual(state.status, .installed)
        XCTAssertEqual(state.runtimeUnitIDs.count, 3)

        // 2. Start
        try executor.start(capabilityID: testCapabilityID)
        let afterStart = try stateStore.service(for: testCapabilityID)
        XCTAssertEqual(afterStart?.status, .running)

        // 3. Status
        let report = try executor.status(capabilityID: testCapabilityID)
        XCTAssertEqual(report.unitStatuses.count, 3)
        XCTAssertEqual(report.status, .running)

        // 4. Stop
        try executor.stop(capabilityID: testCapabilityID)
        let afterStop = try stateStore.service(for: testCapabilityID)
        XCTAssertEqual(afterStop?.status, .stopped)

        // 5. Uninstall
        try executor.uninstall(capabilityID: testCapabilityID)
        let afterUninstall = try stateStore.service(for: testCapabilityID)
        XCTAssertNil(afterUninstall)

        // Verify mock call counts
        let bootstrapCalls = mock.calls.filter { $0.method == "bootstrap" }
        XCTAssertEqual(bootstrapCalls.count, 3, "Should bootstrap 3 units during install")

        let bootoutCalls = mock.calls.filter { $0.method == "bootout" }
        XCTAssertEqual(bootoutCalls.count, 3, "Should bootout 3 units during uninstall")
    }
}

// MARK: - Error Tests

final class ExecutorErrorTests: XCTestCase {

    func testEquality() {
        let a = ExecutorError.notInstalled(capabilityID: "c")
        let b = ExecutorError.notInstalled(capabilityID: "c")
        XCTAssertEqual(a, b)
    }

    func testInequality() {
        let a = ExecutorError.notInstalled(capabilityID: "c")
        let b = ExecutorError.alreadyInstalled(capabilityID: "c")
        XCTAssertNotEqual(a, b)
    }

    func testNoToolingLeaksInErrorCases() {
        let errors: [ExecutorError] = [
            .alreadyInstalled(capabilityID: "c"),
            .notInstalled(capabilityID: "c"),
            .planningFailed(capabilityID: "c", detail: "d"),
            .unsupportedRuntime(capabilityID: "c", unitID: "u", detail: "d"),
            .artifactInstallFailed(capabilityID: "c", unitID: "u", detail: "d"),
            .preparationFailed(capabilityID: "c", unitID: "u", detail: "d"),
            .serviceInstallFailed(capabilityID: "c", unitID: "u", detail: "d"),
            .serviceUninstallFailed(capabilityID: "c", unitID: "u", detail: "d"),
            .startFailed(capabilityID: "c", unitID: "u", detail: "d"),
            .stopFailed(capabilityID: "c", unitID: "u", detail: "d"),
            .statusQueryFailed(capabilityID: "c", detail: "d"),
        ]
        let forbidden = [
            "launchctl", "bootstrap", "bootout", "pip",
            "python", "brew", "PATH", "venv",
        ]

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
