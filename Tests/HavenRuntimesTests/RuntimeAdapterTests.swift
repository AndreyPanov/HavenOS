import XCTest
import HavenCore
@testable import HavenRuntimes

// MARK: - Registry Tests

final class RuntimeAdapterRegistryTests: XCTestCase {

    func testDefaultRegistryContainsNativeAdapter() {
        let registry = RuntimeAdapterRegistry.makeDefault()
        XCTAssertNotNil(registry.adapter(for: .native))
    }

    func testDefaultRegistryContainsPythonAdapter() {
        let registry = RuntimeAdapterRegistry.makeDefault()
        XCTAssertNotNil(registry.adapter(for: .python))
    }

    func testAdapterLookupReturnsCorrectType() {
        let registry = RuntimeAdapterRegistry.makeDefault()
        XCTAssertEqual(registry.adapter(for: .native)?.runtimeType, .native)
        XCTAssertEqual(registry.adapter(for: .python)?.runtimeType, .python)
    }

    func testSupportedRuntimeTypes() {
        let registry = RuntimeAdapterRegistry.makeDefault()
        XCTAssertEqual(registry.supportedRuntimeTypes, [.native, .python])
    }

    func testEmptyRegistryReturnsNil() {
        let registry = RuntimeAdapterRegistry(adapters: [])
        XCTAssertNil(registry.adapter(for: .native))
        XCTAssertNil(registry.adapter(for: .python))
    }

    func testRegistryPrepareThrowsForUnsupportedType() {
        let registry = RuntimeAdapterRegistry(adapters: []) // no adapters
        let unit = RuntimeUnit(
            id: "unit.x", bundleID: "b", runtimeType: .native,
            installSource: "/bin/x", launchArguments: ["/bin/x"]
        )
        let planned = makePlannedUnit(from: unit)
        let layout = makeLayout()

        XCTAssertThrowsError(
            try registry.prepare(unit: unit, plannedUnit: planned, serviceLayout: layout)
        ) { error in
            XCTAssertEqual(
                error as? RuntimeAdapterError,
                .unsupportedRuntimeType(unitID: "unit.x", runtimeType: "native")
            )
        }
    }

    func testRegistryConveniencePrepareSucceeds() throws {
        let registry = RuntimeAdapterRegistry.makeDefault()
        let unit = RuntimeUnit(
            id: "unit.db", bundleID: "b", runtimeType: .native,
            installSource: "/opt/haven/bin/db",
            launchArguments: ["/opt/haven/bin/db", "--datadir", "/data"]
        )
        let planned = makePlannedUnit(from: unit)
        let layout = makeLayout()

        let prepared = try registry.prepare(
            unit: unit, plannedUnit: planned, serviceLayout: layout
        )
        XCTAssertEqual(prepared.unitID, "unit.db")
        XCTAssertEqual(prepared.runtimeType, .native)
    }
}

// MARK: - NativeRuntimeAdapter Tests

final class NativeRuntimeAdapterTests: XCTestCase {

    private let adapter = NativeRuntimeAdapter()

    func testRuntimeType() {
        XCTAssertEqual(adapter.runtimeType, .native)
    }

    func testSuccessfulPreparation() throws {
        let unit = RuntimeUnit(
            id: "haven.unit.test-db",
            bundleID: "haven.bundle.test-library-basic",
            runtimeType: .native,
            installSource: "/opt/haven/bin/test-db",
            launchArguments: ["/opt/haven/bin/test-db", "--datadir", "/data/db"],
            healthcheck: Healthcheck(type: .tcp, target: "localhost:5432", intervalSeconds: 10, retries: 3),
            port: 5432,
            environment: ["DB_DATA": "/data"]
        )
        let planned = makePlannedUnit(
            from: unit,
            resolvedArgs: ["/opt/haven/bin/test-db", "--datadir", "/srv/data/db"],
            resolvedEnv: ["DB_DATA": "/srv/data"],
            resolvedHealthcheck: Healthcheck(type: .tcp, target: "localhost:5432", intervalSeconds: 10, retries: 3),
            port: PlannedPort(number: 5432, source: .spec)
        )
        let layout = makeLayout()

        let prepared = try adapter.prepare(
            unit: unit, plannedUnit: planned, serviceLayout: layout
        )

        // Executable path matches install source
        XCTAssertEqual(prepared.executableURL.path, "/opt/haven/bin/test-db")

        // Arguments are the resolved ones
        XCTAssertEqual(prepared.arguments, ["/opt/haven/bin/test-db", "--datadir", "/srv/data/db"])

        // Environment is the resolved one
        XCTAssertEqual(prepared.environment["DB_DATA"], "/srv/data")

        // Working directory is the service root
        XCTAssertEqual(prepared.workingDirectory, layout.serviceRoot)

        // Managed directories include the standard service layout
        XCTAssertTrue(prepared.managedDirectories.contains(layout.data))
        XCTAssertTrue(prepared.managedDirectories.contains(layout.config))
        XCTAssertTrue(prepared.managedDirectories.contains(layout.logs))
        XCTAssertTrue(prepared.managedDirectories.contains(layout.run))

        // Runtime type
        XCTAssertEqual(prepared.runtimeType, .native)

        // Healthcheck preserved
        XCTAssertEqual(prepared.healthcheck?.type, .tcp)
        XCTAssertEqual(prepared.healthcheck?.target, "localhost:5432")

        // Port preserved
        XCTAssertEqual(prepared.port, 5432)

        // Dependencies preserved
        XCTAssertEqual(prepared.dependsOn, [])
    }

    func testPreparationWithDependencies() throws {
        let unit = RuntimeUnit(
            id: "haven.unit.test-web",
            bundleID: "b",
            runtimeType: .native,
            installSource: "/opt/haven/bin/test-web",
            launchArguments: ["/opt/haven/bin/test-web"],
            dependsOn: ["haven.unit.test-worker"]
        )
        let planned = makePlannedUnit(from: unit, dependsOn: ["haven.unit.test-worker"])
        let layout = makeLayout()

        let prepared = try adapter.prepare(
            unit: unit, plannedUnit: planned, serviceLayout: layout
        )
        XCTAssertEqual(prepared.dependsOn, ["haven.unit.test-worker"])
    }

    func testFailsOnEmptyInstallSource() {
        let unit = RuntimeUnit(
            id: "unit.bad", bundleID: "b", runtimeType: .native,
            installSource: "  ", launchArguments: ["/bin/x"]
        )
        let planned = makePlannedUnit(from: unit)
        let layout = makeLayout()

        XCTAssertThrowsError(
            try adapter.prepare(unit: unit, plannedUnit: planned, serviceLayout: layout)
        ) { error in
            XCTAssertEqual(
                error as? RuntimeAdapterError,
                .missingInstallSource(unitID: "unit.bad")
            )
        }
    }

    func testFailsOnEmptyLaunchArguments() {
        let unit = RuntimeUnit(
            id: "unit.bad", bundleID: "b", runtimeType: .native,
            installSource: "/bin/x", launchArguments: ["/bin/x"]
        )
        // Create a planned unit with empty resolved arguments
        let planned = makePlannedUnit(from: unit, resolvedArgs: [])
        let layout = makeLayout()

        XCTAssertThrowsError(
            try adapter.prepare(unit: unit, plannedUnit: planned, serviceLayout: layout)
        ) { error in
            XCTAssertEqual(
                error as? RuntimeAdapterError,
                .missingLaunchArguments(unitID: "unit.bad")
            )
        }
    }

    func testPathsAreDeterministicUnderServiceLayout() throws {
        let unit = RuntimeUnit(
            id: "unit.a", bundleID: "b", runtimeType: .native,
            installSource: "/opt/haven/bin/svc-a",
            launchArguments: ["/opt/haven/bin/svc-a"]
        )
        let layout = makeLayout(capabilityID: "haven.capability.my-service")
        let planned = makePlannedUnit(from: unit)

        let prepared = try adapter.prepare(
            unit: unit, plannedUnit: planned, serviceLayout: layout
        )

        // Working directory should be under the service layout
        XCTAssertTrue(prepared.workingDirectory.path.contains("haven.capability.my-service"))
    }

    func testTeardownIsNoOp() throws {
        let unit = RuntimeUnit(
            id: "unit.a", bundleID: "b", runtimeType: .native,
            installSource: "/bin/x", launchArguments: ["/bin/x"]
        )
        let layout = makeLayout()
        let planned = makePlannedUnit(from: unit)
        let prepared = try adapter.prepare(
            unit: unit, plannedUnit: planned, serviceLayout: layout
        )

        // Should not throw
        XCTAssertNoThrow(try adapter.teardown(
            preparedRuntime: prepared, serviceLayout: layout
        ))
    }
}

// MARK: - PythonRuntimeAdapter Tests

final class PythonRuntimeAdapterTests: XCTestCase {

    private let adapter = PythonRuntimeAdapter()

    func testRuntimeType() {
        XCTAssertEqual(adapter.runtimeType, .python)
    }

    func testSuccessfulPreparation() throws {
        let unit = RuntimeUnit(
            id: "haven.unit.py-app",
            bundleID: "haven.bundle.py-svc",
            runtimeType: .python,
            installSource: "/opt/haven/packages/py-app",
            launchArguments: ["-m", "pyapp", "--serve"],
            healthcheck: Healthcheck(type: .http, target: "http://localhost:9000/health", intervalSeconds: 15, retries: 3),
            port: 9000,
            environment: ["APP_PORT": "9000"]
        )
        let planned = makePlannedUnit(
            from: unit,
            resolvedArgs: ["-m", "pyapp", "--serve"],
            resolvedEnv: ["APP_PORT": "9000"],
            resolvedHealthcheck: Healthcheck(type: .http, target: "http://localhost:9000/health", intervalSeconds: 15, retries: 3),
            port: PlannedPort(number: 9000, source: .spec)
        )
        let layout = makeLayout(capabilityID: "haven.capability.py-svc")

        let prepared = try adapter.prepare(
            unit: unit, plannedUnit: planned, serviceLayout: layout
        )

        // Executable should be the venv python
        let expectedVenvRoot = layout.run
            .appendingPathComponent("venvs")
            .appendingPathComponent("haven.unit.py-app")
        let expectedPython = expectedVenvRoot
            .appendingPathComponent("bin")
            .appendingPathComponent("python3")
        XCTAssertEqual(prepared.executableURL, expectedPython)

        // Arguments should start with the venv python, then the original args
        XCTAssertEqual(prepared.arguments.first, expectedPython.path)
        XCTAssertTrue(prepared.arguments.contains("-m"))
        XCTAssertTrue(prepared.arguments.contains("pyapp"))
        XCTAssertTrue(prepared.arguments.contains("--serve"))

        // Environment should include VIRTUAL_ENV and a controlled PATH
        XCTAssertEqual(prepared.environment["VIRTUAL_ENV"], expectedVenvRoot.path)
        XCTAssertTrue(prepared.environment["PATH"]?.hasPrefix(expectedVenvRoot.appendingPathComponent("bin").path) == true)
        // Original env vars preserved
        XCTAssertEqual(prepared.environment["APP_PORT"], "9000")

        // Working directory is the service root
        XCTAssertEqual(prepared.workingDirectory, layout.serviceRoot)

        // Managed directories include the venv root
        XCTAssertTrue(prepared.managedDirectories.contains(expectedVenvRoot))
        // And the standard service layout dirs
        XCTAssertTrue(prepared.managedDirectories.contains(layout.data))

        // Runtime type
        XCTAssertEqual(prepared.runtimeType, .python)

        // Healthcheck preserved
        XCTAssertEqual(prepared.healthcheck?.type, .http)
        XCTAssertEqual(prepared.port, 9000)
        XCTAssertEqual(prepared.dependsOn, [])
    }

    func testVenvDirectoryIsDeterministic() {
        let layout = makeLayout(capabilityID: "haven.capability.svc")
        let venv = adapter.venvDirectory(for: "haven.unit.py-app", serviceLayout: layout)

        // Should be under run/venvs/<unit-id>
        XCTAssertTrue(venv.path.contains("run/venvs/haven.unit.py-app"))
        XCTAssertTrue(venv.path.contains("haven.capability.svc"))
    }

    func testFailsOnEmptyInstallSource() {
        let unit = RuntimeUnit(
            id: "unit.bad", bundleID: "b", runtimeType: .python,
            installSource: "", launchArguments: ["-m", "app"]
        )
        let planned = makePlannedUnit(from: unit)
        let layout = makeLayout()

        XCTAssertThrowsError(
            try adapter.prepare(unit: unit, plannedUnit: planned, serviceLayout: layout)
        ) { error in
            XCTAssertEqual(
                error as? RuntimeAdapterError,
                .missingInstallSource(unitID: "unit.bad")
            )
        }
    }

    func testFailsOnEmptyLaunchArguments() {
        let unit = RuntimeUnit(
            id: "unit.bad", bundleID: "b", runtimeType: .python,
            installSource: "/opt/haven/packages/app", launchArguments: ["-m", "app"]
        )
        let planned = makePlannedUnit(from: unit, resolvedArgs: [])
        let layout = makeLayout()

        XCTAssertThrowsError(
            try adapter.prepare(unit: unit, plannedUnit: planned, serviceLayout: layout)
        ) { error in
            XCTAssertEqual(
                error as? RuntimeAdapterError,
                .missingLaunchArguments(unitID: "unit.bad")
            )
        }
    }

    func testEnvironmentDoesNotLeakSystemPath() throws {
        let unit = RuntimeUnit(
            id: "unit.py", bundleID: "b", runtimeType: .python,
            installSource: "/opt/haven/packages/app",
            launchArguments: ["-m", "app"]
        )
        let planned = makePlannedUnit(from: unit)
        let layout = makeLayout()

        let prepared = try adapter.prepare(
            unit: unit, plannedUnit: planned, serviceLayout: layout
        )

        // PATH should be controlled — starts with the venv bin, not $PATH
        let path = try XCTUnwrap(prepared.environment["PATH"])
        XCTAssertTrue(path.contains("venvs"), "PATH should reference the venv")
        XCTAssertFalse(path.contains("$PATH"), "PATH should not reference $PATH")
        // Should not contain common user PATH entries
        XCTAssertFalse(path.contains("/usr/local/bin"), "PATH should not include /usr/local/bin")
        XCTAssertFalse(path.contains("homebrew"), "PATH should not reference Homebrew")
    }

    func testTeardownDoesNotThrow() throws {
        let unit = RuntimeUnit(
            id: "unit.py", bundleID: "b", runtimeType: .python,
            installSource: "/opt/haven/packages/app",
            launchArguments: ["-m", "app"]
        )
        let layout = makeLayout()
        let planned = makePlannedUnit(from: unit)
        let prepared = try adapter.prepare(
            unit: unit, plannedUnit: planned, serviceLayout: layout
        )

        XCTAssertNoThrow(try adapter.teardown(
            preparedRuntime: prepared, serviceLayout: layout
        ))
    }
}

// MARK: - PreparedRuntime Tests

final class PreparedRuntimeTests: XCTestCase {

    func testEquality() {
        let a = PreparedRuntime(
            unitID: "u.1",
            executableURL: URL(fileURLWithPath: "/bin/x"),
            arguments: ["/bin/x"],
            environment: [:],
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            managedDirectories: [],
            runtimeType: .native,
            healthcheck: nil,
            port: nil,
            dependsOn: []
        )
        let b = PreparedRuntime(
            unitID: "u.1",
            executableURL: URL(fileURLWithPath: "/bin/x"),
            arguments: ["/bin/x"],
            environment: [:],
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            managedDirectories: [],
            runtimeType: .native,
            healthcheck: nil,
            port: nil,
            dependsOn: []
        )
        XCTAssertEqual(a, b)
    }

    func testInequality() {
        let a = PreparedRuntime(
            unitID: "u.1",
            executableURL: URL(fileURLWithPath: "/bin/x"),
            arguments: ["/bin/x"],
            environment: [:],
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            managedDirectories: [],
            runtimeType: .native,
            healthcheck: nil,
            port: nil,
            dependsOn: []
        )
        let b = PreparedRuntime(
            unitID: "u.2",
            executableURL: URL(fileURLWithPath: "/bin/y"),
            arguments: ["/bin/y"],
            environment: [:],
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            managedDirectories: [],
            runtimeType: .python,
            healthcheck: nil,
            port: nil,
            dependsOn: []
        )
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - RuntimeAdapterError Tests

final class RuntimeAdapterErrorTests: XCTestCase {

    func testErrorEquality() {
        let a = RuntimeAdapterError.missingInstallSource(unitID: "u.1")
        let b = RuntimeAdapterError.missingInstallSource(unitID: "u.1")
        XCTAssertEqual(a, b)
    }

    func testErrorInequality() {
        let a = RuntimeAdapterError.missingInstallSource(unitID: "u.1")
        let b = RuntimeAdapterError.missingInstallSource(unitID: "u.2")
        XCTAssertNotEqual(a, b)
    }

    func testNoUserFacingToolingInErrorCases() {
        // Verify that error case names and parameters don't mention
        // pip, python, brew, PATH, launchctl, or venv in their public surface.
        let errors: [RuntimeAdapterError] = [
            .missingInstallSource(unitID: "u"),
            .executableNotFound(unitID: "u", path: "/x"),
            .missingLaunchArguments(unitID: "u"),
            .unsupportedRuntimeType(unitID: "u", runtimeType: "native"),
            .environmentSetupFailed(unitID: "u", reason: "test"),
        ]
        let forbidden = ["pip", "python", "brew", "PATH", "launchctl", "venv"]

        for error in errors {
            let description = String(describing: error)
            for word in forbidden {
                // Only check case names, not values we pass in
                let casePrefix = description.prefix(while: { $0 != "(" })
                XCTAssertFalse(
                    casePrefix.contains(word),
                    "Error case name should not contain '\(word)': \(casePrefix)"
                )
            }
        }
    }
}

// MARK: - Test Helpers

private let testBaseDir = URL(fileURLWithPath: "/tmp/haven-test")

private func makeLayout(
    capabilityID: String = "haven.capability.test-library"
) -> ServiceDirectoryLayout {
    ServiceDirectoryLayout(
        servicesDirectory: testBaseDir.appendingPathComponent("Services"),
        capabilityID: capabilityID
    )
}

private func makePlannedUnit(
    from unit: RuntimeUnit,
    resolvedArgs: [String]? = nil,
    resolvedEnv: [String: String]? = nil,
    resolvedHealthcheck: Healthcheck? = nil,
    port: PlannedPort? = nil,
    dependsOn: [String]? = nil
) -> PlannedRuntimeUnit {
    PlannedRuntimeUnit(
        spec: unit,
        resolvedLaunchArguments: resolvedArgs ?? unit.launchArguments,
        resolvedEnvironment: resolvedEnv ?? unit.environment,
        port: port ?? (unit.port.map { PlannedPort(number: $0, source: .spec) }),
        resolvedHealthcheck: resolvedHealthcheck ?? unit.healthcheck,
        dependsOn: dependsOn ?? unit.dependsOn,
        templateContext: TemplateContext(values: [:])
    )
}
