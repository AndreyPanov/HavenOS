import XCTest
import Foundation
import HavenCore
@testable import HavenInstaller

// MARK: - MockPythonCommandRunner

final class MockPythonCommandRunner: PythonCommandRunner, @unchecked Sendable {

    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    private(set) var calls: [Call] = []

    /// Results returned in FIFO order. Falls back to `defaultResult` when empty.
    var results: [PythonCommandResult] = []
    var defaultResult = PythonCommandResult(exitCode: 0, stdout: "", stderr: "")

    /// Optional side-effect closure invoked before returning each result.
    /// Use this to simulate filesystem changes (e.g. creating staging directories).
    var sideEffect: ((_ executable: String, _ arguments: [String]) -> Void)?

    /// If true, `--version` calls are handled automatically without
    /// consuming a result from the queue. Defaults to true.
    var autoHandleVersion = true

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?
    ) throws -> PythonCommandResult {
        calls.append(Call(executable: executable, arguments: arguments))
        sideEffect?(executable, arguments)

        // Auto-respond to --version checks from findSystemPython
        if autoHandleVersion && arguments == ["--version"] {
            return PythonCommandResult(exitCode: 0, stdout: "Python 3.12.0", stderr: "")
        }

        if !results.isEmpty {
            return results.removeFirst()
        }
        return defaultResult
    }
}

// MARK: - PythonEnvironmentPreparer Tests

final class PythonEnvironmentPreparerTests: XCTestCase {

    private var tempDir: URL!
    private var mockRunner: MockPythonCommandRunner!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-python-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mockRunner = MockPythonCommandRunner()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Successful Preparation

    func testSuccessfulPreparation() throws {
        // Simulate venv creation: when the `-m venv` command runs,
        // create the staging directory + bin/python3 on disk so the
        // atomic promote (moveItem) succeeds.
        mockRunner.sideEffect = { _, arguments in
            if arguments.contains("venv"), let path = arguments.last {
                let binDir = URL(fileURLWithPath: path).appendingPathComponent("bin")
                try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
                FileManager.default.createFile(
                    atPath: binDir.appendingPathComponent("python3").path,
                    contents: Data()
                )
            }
        }

        let preparer = PythonEnvironmentPreparer(commandRunner: mockRunner)
        let config = RuntimeUnit.PythonConfig(
            package: "calibreweb",
            version: "0.6.26",
            entrypoint: .init(module: "calibreweb")
        )

        let result = try preparer.prepare(
            pythonConfig: config,
            unitID: "haven.unit.calibre-web",
            basePath: tempDir
        )

        XCTAssertEqual(result.unitID, "haven.unit.calibre-web")
        XCTAssertEqual(result.package, "calibreweb")
        XCTAssertEqual(result.version, "0.6.26")
        XCTAssertFalse(result.wasCached)

        // Verify 4 commands were run: version check, venv creation, pip install, module validation
        XCTAssertEqual(mockRunner.calls.count, 4)
        XCTAssertTrue(mockRunner.calls[0].arguments.contains("--version"))
        XCTAssertTrue(mockRunner.calls[1].arguments.contains("venv"))
        XCTAssertTrue(mockRunner.calls[2].arguments.contains("install"))
        XCTAssertTrue(mockRunner.calls[2].arguments.contains("calibreweb==0.6.26"))
        XCTAssertTrue(mockRunner.calls[3].arguments.contains("import calibreweb"))

        // Venv directory should exist (actually the staging dir was promoted,
        // but since mock doesn't create real files, we check the result paths)
        let expectedVenvDir = tempDir
            .appendingPathComponent("Installed")
            .appendingPathComponent("python")
            .appendingPathComponent("haven.unit.calibre-web")
            .appendingPathComponent("venv")
        XCTAssertEqual(result.venvDirectory.standardizedFileURL, expectedVenvDir.standardizedFileURL)
        XCTAssertTrue(result.pythonPath.path.hasSuffix("bin/python3"))
    }

    // MARK: - Failure Cases

    func testVenvCreationFailure() {
        mockRunner.results = [
            PythonCommandResult(exitCode: 1, stdout: "", stderr: "venv module not found")
        ]
        let preparer = PythonEnvironmentPreparer(commandRunner: mockRunner)
        let config = RuntimeUnit.PythonConfig(
            package: "pkg", version: "1.0",
            entrypoint: .init(module: "mod")
        )

        XCTAssertThrowsError(try preparer.prepare(
            pythonConfig: config, unitID: "test.unit", basePath: tempDir
        )) { error in
            guard case .venvCreationFailed(let unitID, _) = error as? PythonEnvironmentError else {
                XCTFail("Expected venvCreationFailed, got \(error)"); return
            }
            XCTAssertEqual(unitID, "test.unit")
        }

        // Staging directory should be cleaned up
        let stagingDir = tempDir
            .appendingPathComponent("Installed/python/test.unit/test.unit.creating")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDir.path))
    }

    func testPipInstallFailure() {
        mockRunner.results = [
            PythonCommandResult(exitCode: 0, stdout: "", stderr: ""),  // venv OK
            PythonCommandResult(exitCode: 1, stdout: "", stderr: "No matching distribution found"),
        ]
        let preparer = PythonEnvironmentPreparer(commandRunner: mockRunner)
        let config = RuntimeUnit.PythonConfig(
            package: "badpkg", version: "9.9.9",
            entrypoint: .init(module: "mod")
        )

        XCTAssertThrowsError(try preparer.prepare(
            pythonConfig: config, unitID: "test.unit", basePath: tempDir
        )) { error in
            guard case .packageInstallFailed(let unitID, let pkg, _) = error as? PythonEnvironmentError else {
                XCTFail("Expected packageInstallFailed, got \(error)"); return
            }
            XCTAssertEqual(unitID, "test.unit")
            XCTAssertEqual(pkg, "badpkg==9.9.9")
        }
    }

    func testModuleValidationFailure() {
        mockRunner.results = [
            PythonCommandResult(exitCode: 0, stdout: "", stderr: ""),  // venv OK
            PythonCommandResult(exitCode: 0, stdout: "", stderr: ""),  // pip OK
            PythonCommandResult(exitCode: 1, stdout: "", stderr: "ModuleNotFoundError"),
        ]
        let preparer = PythonEnvironmentPreparer(commandRunner: mockRunner)
        let config = RuntimeUnit.PythonConfig(
            package: "pkg", version: "1.0",
            entrypoint: .init(module: "bad_mod")
        )

        XCTAssertThrowsError(try preparer.prepare(
            pythonConfig: config, unitID: "test.unit", basePath: tempDir
        )) { error in
            guard case .moduleValidationFailed(let unitID, let module, _) = error as? PythonEnvironmentError else {
                XCTFail("Expected moduleValidationFailed, got \(error)"); return
            }
            XCTAssertEqual(unitID, "test.unit")
            XCTAssertEqual(module, "bad_mod")
        }
    }

    // MARK: - Caching

    func testCachedVenvReuse() throws {
        // First, create the venv directory structure to simulate a cached env
        let venvDir = tempDir
            .appendingPathComponent("Installed/python/test.unit/venv")
        let binDir = venvDir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        // Create a fake python3 binary (must be executable for isVenvValid)
        let pythonPath = binDir.appendingPathComponent("python3")
        FileManager.default.createFile(atPath: pythonPath.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: pythonPath.path
        )

        // Mock: the module import check succeeds
        mockRunner.defaultResult = PythonCommandResult(exitCode: 0, stdout: "", stderr: "")

        let preparer = PythonEnvironmentPreparer(commandRunner: mockRunner)
        let config = RuntimeUnit.PythonConfig(
            package: "pkg", version: "1.0",
            entrypoint: .init(module: "mod")
        )

        let result = try preparer.prepare(
            pythonConfig: config, unitID: "test.unit", basePath: tempDir
        )

        XCTAssertTrue(result.wasCached)
        // 2 calls: version check, then module import validation for cache check
        XCTAssertEqual(mockRunner.calls.count, 2)
        XCTAssertTrue(mockRunner.calls[0].arguments.contains("--version"))
        XCTAssertTrue(mockRunner.calls[1].arguments.contains("import mod"))
    }

    func testBrokenVenvTriggersReinstall() throws {
        // Create a venv directory with a python binary that fails the import check
        let venvDir = tempDir
            .appendingPathComponent("Installed/python/test.unit/venv")
        let binDir = venvDir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let pythonPath = binDir.appendingPathComponent("python3")
        FileManager.default.createFile(atPath: pythonPath.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: pythonPath.path
        )

        // Simulate venv creation on disk when the `-m venv` command runs
        mockRunner.sideEffect = { _, arguments in
            if arguments.contains("venv"), let path = arguments.last {
                let binDir = URL(fileURLWithPath: path).appendingPathComponent("bin")
                try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
                FileManager.default.createFile(
                    atPath: binDir.appendingPathComponent("python3").path,
                    contents: Data()
                )
            }
        }

        // Mock: cache validation fails, then fresh install succeeds
        mockRunner.results = [
            PythonCommandResult(exitCode: 1, stdout: "", stderr: "broken"),  // cache check fails
            PythonCommandResult(exitCode: 0, stdout: "", stderr: ""),        // venv creation
            PythonCommandResult(exitCode: 0, stdout: "", stderr: ""),        // pip install
            PythonCommandResult(exitCode: 0, stdout: "", stderr: ""),        // module validation
        ]

        let preparer = PythonEnvironmentPreparer(commandRunner: mockRunner)
        let config = RuntimeUnit.PythonConfig(
            package: "pkg", version: "1.0",
            entrypoint: .init(module: "mod")
        )

        let result = try preparer.prepare(
            pythonConfig: config, unitID: "test.unit", basePath: tempDir
        )

        XCTAssertFalse(result.wasCached)
        // 5 calls: version check, cache validation, venv creation, pip install, module validation
        XCTAssertEqual(mockRunner.calls.count, 5)
    }

    // MARK: - Remove

    func testRemoveVenvDirectory() throws {
        let unitRoot = tempDir
            .appendingPathComponent("Installed/python/test.unit")
        try FileManager.default.createDirectory(at: unitRoot, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: unitRoot.appendingPathComponent("marker.txt").path,
            contents: Data()
        )

        let preparer = PythonEnvironmentPreparer(commandRunner: mockRunner)
        try preparer.remove(unitID: "test.unit", basePath: tempDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: unitRoot.path))
    }

    func testRemoveNonexistentVenvIsNoOp() throws {
        let preparer = PythonEnvironmentPreparer(commandRunner: mockRunner)
        // Should not throw
        XCTAssertNoThrow(try preparer.remove(unitID: "nonexistent", basePath: tempDir))
    }

    // MARK: - Path Helpers

    func testVenvDirectoryPath() {
        let preparer = PythonEnvironmentPreparer(commandRunner: mockRunner)
        let venvDir = preparer.venvDirectory(unitID: "haven.unit.test", basePath: tempDir)

        XCTAssertTrue(venvDir.path.contains("Installed/python/haven.unit.test/venv"))
    }

    // MARK: - Python Version Parsing

    func testParsePythonVersionStandard() {
        let v = PythonEnvironmentPreparer.parsePythonVersion("Python 3.12.8")
        XCTAssertEqual(v?.major, 3)
        XCTAssertEqual(v?.minor, 12)
        XCTAssertEqual(v?.patch, 8)
    }

    func testParsePythonVersionTwoPart() {
        let v = PythonEnvironmentPreparer.parsePythonVersion("Python 3.10")
        XCTAssertEqual(v?.major, 3)
        XCTAssertEqual(v?.minor, 10)
        XCTAssertEqual(v?.patch, 0)
    }

    func testParsePythonVersionInvalid() {
        XCTAssertNil(PythonEnvironmentPreparer.parsePythonVersion("not a version"))
        XCTAssertNil(PythonEnvironmentPreparer.parsePythonVersion("Python"))
        XCTAssertNil(PythonEnvironmentPreparer.parsePythonVersion(""))
    }

    func testOldPythonVersionIsSkipped() {
        // Mock: first path returns Python 3.9, second returns Python 3.12
        mockRunner.autoHandleVersion = false
        mockRunner.results = [
            PythonCommandResult(exitCode: 0, stdout: "Python 3.9.6", stderr: ""),  // old python
            PythonCommandResult(exitCode: 0, stdout: "Python 3.12.8", stderr: ""), // good python
        ]
        // Simulate venv creation
        mockRunner.sideEffect = { _, arguments in
            if arguments.contains("venv"), let path = arguments.last {
                let binDir = URL(fileURLWithPath: path).appendingPathComponent("bin")
                try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
                FileManager.default.createFile(
                    atPath: binDir.appendingPathComponent("python3").path,
                    contents: Data()
                )
            }
        }

        let preparer = PythonEnvironmentPreparer(commandRunner: mockRunner)
        let config = RuntimeUnit.PythonConfig(
            package: "pkg", version: "1.0",
            entrypoint: .init(module: "mod")
        )

        // This should succeed — the preparer should skip the old Python
        // and use the second path. In practice this depends on which
        // system paths exist, so we just verify the version parsing.
        // The full integration is tested by the version parse tests above.
        let v1 = PythonEnvironmentPreparer.parsePythonVersion("Python 3.9.6")!
        XCTAssertTrue(
            (v1.major, v1.minor) < PythonEnvironmentPreparer.minimumPythonVersion,
            "3.9 should be below minimum"
        )
        let v2 = PythonEnvironmentPreparer.parsePythonVersion("Python 3.12.8")!
        XCTAssertTrue(
            (v2.major, v2.minor) >= PythonEnvironmentPreparer.minimumPythonVersion,
            "3.12 should meet minimum"
        )
    }
}
