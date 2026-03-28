import XCTest
import HavenCore

// MARK: - HavenPaths Tests

final class HavenPathsTests: XCTestCase {

    private let base = URL(fileURLWithPath: "/tmp/haven-test")

    func testStateDirectory() {
        let paths = HavenPaths(base: base)
        XCTAssertEqual(paths.stateDirectory.path, "/tmp/haven-test/State")
    }

    func testDownloadsDirectory() {
        let paths = HavenPaths(base: base)
        XCTAssertEqual(paths.downloadsDirectory.path, "/tmp/haven-test/Downloads")
    }

    func testServicesDirectory() {
        let paths = HavenPaths(base: base)
        XCTAssertEqual(paths.servicesDirectory.path, "/tmp/haven-test/Services")
    }

    func testStateFile() {
        let paths = HavenPaths(base: base)
        XCTAssertEqual(paths.stateFile.path, "/tmp/haven-test/State/services.json")
    }

    func testTopLevelDirectories() {
        let paths = HavenPaths(base: base)
        let dirs = paths.topLevelDirectories.map(\.path)
        XCTAssertEqual(dirs, [
            "/tmp/haven-test/State",
            "/tmp/haven-test/Downloads",
            "/tmp/haven-test/Services",
        ])
    }

    func testServiceLayoutDelegation() {
        let paths = HavenPaths(base: base)
        let layout = paths.serviceLayout(for: "haven.capability.test-library")
        XCTAssertEqual(
            layout.serviceRoot.path,
            "/tmp/haven-test/Services/haven.capability.test-library"
        )
    }

    func testEquality() {
        let a = HavenPaths(base: base)
        let b = HavenPaths(base: base)
        XCTAssertEqual(a, b)
    }
}

// MARK: - ServiceDirectoryLayout Tests

final class ServiceDirectoryLayoutTests: XCTestCase {

    private let servicesDir = URL(fileURLWithPath: "/tmp/haven-test/Services")

    func testServiceRoot() {
        let layout = ServiceDirectoryLayout(
            servicesDirectory: servicesDir,
            capabilityID: "haven.capability.test-library"
        )
        XCTAssertEqual(
            layout.serviceRoot.path,
            "/tmp/haven-test/Services/haven.capability.test-library"
        )
    }

    func testSubdirectories() {
        let layout = ServiceDirectoryLayout(
            servicesDirectory: servicesDir,
            capabilityID: "cap.x"
        )
        let root = "/tmp/haven-test/Services/cap.x"
        XCTAssertEqual(layout.data.path, "\(root)/data")
        XCTAssertEqual(layout.config.path, "\(root)/config")
        XCTAssertEqual(layout.logs.path, "\(root)/logs")
        XCTAssertEqual(layout.run.path, "\(root)/run")
    }

    func testAllDirectories() {
        let layout = ServiceDirectoryLayout(
            servicesDirectory: servicesDir,
            capabilityID: "cap.x"
        )
        XCTAssertEqual(layout.allDirectories.count, 5)
        XCTAssertEqual(layout.allDirectories[0], layout.serviceRoot)
        XCTAssertEqual(layout.allDirectories[1], layout.data)
        XCTAssertEqual(layout.allDirectories[2], layout.config)
        XCTAssertEqual(layout.allDirectories[3], layout.logs)
        XCTAssertEqual(layout.allDirectories[4], layout.run)
    }

    func testCodableRoundTrip() throws {
        let original = ServiceDirectoryLayout(
            servicesDirectory: servicesDir,
            capabilityID: "haven.capability.test-library"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ServiceDirectoryLayout.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testEquality() {
        let a = ServiceDirectoryLayout(servicesDirectory: servicesDir, capabilityID: "cap.x")
        let b = ServiceDirectoryLayout(servicesDirectory: servicesDir, capabilityID: "cap.x")
        XCTAssertEqual(a, b)
    }
}

// MARK: - StoredServiceState Tests

final class StoredServiceStateTests: XCTestCase {

    private func makeSampleState() -> StoredServiceState {
        let layout = ServiceDirectoryLayout(
            servicesDirectory: URL(fileURLWithPath: "/tmp/haven/Services"),
            capabilityID: "haven.capability.test-library"
        )
        return StoredServiceState(
            capabilityID: "haven.capability.test-library",
            bundleID: "haven.bundle.test-library-basic",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            status: .installed,
            resolvedSettings: ["data_path": "/srv/data", "port": "8080"],
            portAssignments: [
                StoredPortAssignment(unitID: "haven.unit.test-web", port: 8080)
            ],
            runtimeUnitIDs: [
                "haven.unit.test-db",
                "haven.unit.test-worker",
                "haven.unit.test-web",
            ],
            directoryLayout: layout
        )
    }

    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = makeSampleState()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(StoredServiceState.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testStatusValues() {
        XCTAssertEqual(ServiceStatus.installed.rawValue, "installed")
        XCTAssertEqual(ServiceStatus.running.rawValue, "running")
        XCTAssertEqual(ServiceStatus.stopped.rawValue, "stopped")
        XCTAssertEqual(ServiceStatus.failed.rawValue, "failed")
    }
}

// MARK: - FileStateStore Tests

final class FileStateStoreTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-state-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        if let tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        super.tearDown()
    }

    private func makePaths() -> HavenPaths {
        HavenPaths(base: tmpDir)
    }

    private func makeStore() -> FileStateStore {
        FileStateStore(paths: makePaths())
    }

    private func makeSampleService(
        capabilityID: String = "haven.capability.test-library",
        status: ServiceStatus = .installed
    ) -> StoredServiceState {
        let paths = makePaths()
        let layout = paths.serviceLayout(for: capabilityID)
        return StoredServiceState(
            capabilityID: capabilityID,
            bundleID: "haven.bundle.test-library-basic",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: status,
            resolvedSettings: ["data_path": "/srv/data", "port": "8080"],
            portAssignments: [
                StoredPortAssignment(unitID: "haven.unit.test-web", port: 8080)
            ],
            runtimeUnitIDs: [
                "haven.unit.test-db",
                "haven.unit.test-worker",
                "haven.unit.test-web",
            ],
            directoryLayout: layout
        )
    }

    // MARK: - Empty load

    func testLoadFromMissingFileReturnsEmptyState() throws {
        let store = makeStore()
        let state = try store.load()
        XCTAssertTrue(state.services.isEmpty)
    }

    // MARK: - Save + reload

    func testSaveAndReload() throws {
        let store = makeStore()
        let svc = makeSampleService()
        var state = HavenState()
        state.services[svc.capabilityID] = svc
        try store.save(state)

        let loaded = try store.load()
        XCTAssertEqual(loaded.services.count, 1)
        XCTAssertEqual(loaded.services[svc.capabilityID], svc)
    }

    func testSaveCreatesParentDirectories() throws {
        let store = makeStore()
        let svc = makeSampleService()
        try store.upsert(svc)

        let paths = makePaths()
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: paths.stateFile.path),
            "State file should exist after save"
        )
    }

    // MARK: - Service lookup

    func testServiceLookupFound() throws {
        let store = makeStore()
        let svc = makeSampleService()
        try store.upsert(svc)

        let found = try store.service(for: "haven.capability.test-library")
        XCTAssertEqual(found, svc)
    }

    func testServiceLookupNotFound() throws {
        let store = makeStore()
        let found = try store.service(for: "haven.capability.nonexistent")
        XCTAssertNil(found)
    }

    // MARK: - Upsert

    func testUpsertNewService() throws {
        let store = makeStore()
        let svc = makeSampleService()
        try store.upsert(svc)

        let state = try store.load()
        XCTAssertEqual(state.services.count, 1)
        XCTAssertEqual(state.services[svc.capabilityID]?.status, .installed)
    }

    func testUpsertExistingServiceReplaces() throws {
        let store = makeStore()
        let svc = makeSampleService(status: .installed)
        try store.upsert(svc)

        var updated = svc
        updated.status = .running
        updated.updatedAt = Date(timeIntervalSince1970: 1_700_001_000)
        try store.upsert(updated)

        let state = try store.load()
        XCTAssertEqual(state.services.count, 1)
        XCTAssertEqual(state.services[svc.capabilityID]?.status, .running)
    }

    func testUpsertMultipleServices() throws {
        let store = makeStore()
        let svc1 = makeSampleService(capabilityID: "cap.a")
        let svc2 = makeSampleService(capabilityID: "cap.b")
        try store.upsert(svc1)
        try store.upsert(svc2)

        let state = try store.load()
        XCTAssertEqual(state.services.count, 2)
        XCTAssertNotNil(state.services["cap.a"])
        XCTAssertNotNil(state.services["cap.b"])
    }

    // MARK: - Remove

    func testRemoveExistingService() throws {
        let store = makeStore()
        let svc = makeSampleService()
        try store.upsert(svc)
        try store.remove(capabilityID: svc.capabilityID)

        let state = try store.load()
        XCTAssertTrue(state.services.isEmpty)
    }

    func testRemoveNonexistentServiceIsNoOp() throws {
        let store = makeStore()
        let svc = makeSampleService()
        try store.upsert(svc)
        try store.remove(capabilityID: "haven.capability.nonexistent")

        let state = try store.load()
        XCTAssertEqual(state.services.count, 1)
    }

    // MARK: - Atomic write

    func testAtomicWriteProducesValidJSON() throws {
        let store = makeStore()
        let svc = makeSampleService()
        try store.upsert(svc)

        // Read the raw file and verify it's valid JSON
        let paths = makePaths()
        let data = try Data(contentsOf: paths.stateFile)
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [String: Any], "State file should contain a JSON object")
    }

    func testAtomicWriteNoPartialFile() throws {
        // After a successful write, no temp files should remain
        let store = makeStore()
        try store.upsert(makeSampleService())

        let paths = makePaths()
        let stateDir = paths.stateDirectory
        let contents = try FileManager.default.contentsOfDirectory(
            at: stateDir,
            includingPropertiesForKeys: nil
        )
        let tempFiles = contents.filter { $0.lastPathComponent.hasSuffix(".tmp") }
        XCTAssertTrue(tempFiles.isEmpty, "No temp files should remain: \(tempFiles)")
    }

    // MARK: - Persistence across store instances

    func testPersistenceAcrossInstances() throws {
        let paths = makePaths()
        let store1 = FileStateStore(paths: paths)
        try store1.upsert(makeSampleService())

        // New store instance pointing at the same file
        let store2 = FileStateStore(paths: paths)
        let state = try store2.load()
        XCTAssertEqual(state.services.count, 1)
    }

    // MARK: - Thread safety

    func testConcurrentUpsertsDoNotCorrupt() throws {
        let store = makeStore()
        let iterations = 50
        let queue = DispatchQueue(
            label: "haven.state-test.concurrent",
            attributes: .concurrent
        )
        let group = DispatchGroup()

        for i in 0..<iterations {
            group.enter()
            queue.async {
                defer { group.leave() }
                let svc = self.makeSampleService(
                    capabilityID: "cap.\(i)"
                )
                do {
                    try store.upsert(svc)
                } catch {
                    XCTFail("Concurrent upsert failed: \(error)")
                }
            }
        }

        group.wait()

        // After all concurrent writes, the state should be valid JSON
        // and contain some services (exact count may vary due to
        // read-modify-write races, but no crashes or corrupt files).
        let state = try store.load()
        XCTAssertFalse(state.services.isEmpty, "Should have some services after concurrent writes")
        // Since we lock around the full read-modify-write cycle, we
        // should actually get all of them.
        XCTAssertEqual(state.services.count, iterations,
            "All \(iterations) services should be persisted")
    }

    func testConcurrentReadsDoNotCrash() throws {
        let store = makeStore()
        try store.upsert(makeSampleService())

        let queue = DispatchQueue(
            label: "haven.state-test.reads",
            attributes: .concurrent
        )
        let group = DispatchGroup()

        for _ in 0..<100 {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    _ = try store.load()
                } catch {
                    XCTFail("Concurrent load failed: \(error)")
                }
            }
        }

        group.wait()
    }
}
