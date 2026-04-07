import XCTest
import HavenCore

final class PlannerTests: XCTestCase {

    // MARK: - Helpers

    private let baseDir = URL(fileURLWithPath: "/tmp/haven-test")

    /// Build a registry from the standard test-library examples.
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

    // MARK: - Successful planning

    func testSuccessfulPlanForTestLibrary() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.test-library",
            registry: registry,
            settings: ["data_path": "/my/data"],
            baseDirectory: baseDir
        )

        let svc = plan.service

        // Capability
        XCTAssertEqual(svc.capability.id, "haven.capability.test-library")
        XCTAssertEqual(svc.capability.name, "Test Library")

        // Bundle
        XCTAssertEqual(svc.bundle.id, "haven.bundle.test-library-basic")

        // Resolved settings: user override + default
        XCTAssertEqual(svc.resolvedSettings["data_path"], "/my/data")
        XCTAssertEqual(svc.resolvedSettings["port"], "8080")

        // Directory layout
        XCTAssertTrue(svc.directoryLayout.serviceRoot.path.contains("haven.capability.test-library"))
        XCTAssertTrue(svc.directoryLayout.data.path.hasSuffix("data"))
        XCTAssertTrue(svc.directoryLayout.config.path.hasSuffix("config"))
        XCTAssertTrue(svc.directoryLayout.logs.path.hasSuffix("logs"))
        XCTAssertTrue(svc.directoryLayout.run.path.hasSuffix("run"))

        // Three runtime units in topological order
        XCTAssertEqual(svc.units.count, 3)
        XCTAssertEqual(svc.units[0].spec.id, "haven.unit.test-db")
        XCTAssertEqual(svc.units[1].spec.id, "haven.unit.test-worker")
        XCTAssertEqual(svc.units[2].spec.id, "haven.unit.test-web")

        // Port on the web unit
        XCTAssertEqual(svc.units[2].port?.number, 8080)
        XCTAssertEqual(svc.units[2].port?.source, .spec)
    }

    // MARK: - Placeholder expansion

    func testPlaceholderExpansionInEnvironment() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.test-library",
            registry: registry,
            settings: ["data_path": "/srv/testdata"],
            baseDirectory: baseDir
        )

        // Check the web unit (units[2] after topological sort)
        let webUnit = plan.service.units[2]

        // Environment should have expanded ${port}
        XCTAssertEqual(webUnit.resolvedEnvironment["WEB_PORT"], "8080")

        // ${data_path} should resolve to user-provided value
        XCTAssertEqual(webUnit.resolvedEnvironment["WEB_DATA"], "/srv/testdata")

        // ${logs_dir} should resolve to the planned logs directory
        XCTAssertEqual(
            webUnit.resolvedEnvironment["WEB_LOGS"],
            plan.service.directoryLayout.logs.path
        )
    }

    func testPlaceholderExpansionInLaunchArguments() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.test-library",
            registry: registry,
            settings: ["data_path": "/srv/testdata"],
            baseDirectory: baseDir
        )

        // Check the worker unit (units[1]) — has --config ${config_dir}/worker.toml
        let workerUnit = plan.service.units[1]
        let configDir = plan.service.directoryLayout.config.path

        XCTAssertTrue(
            workerUnit.resolvedLaunchArguments.contains("\(configDir)/worker.toml"),
            "Expected expanded config path, got: \(workerUnit.resolvedLaunchArguments)"
        )
    }

    func testPlaceholderExpansionInHealthcheck() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.test-library",
            registry: registry,
            settings: ["data_path": "/srv/testdata"],
            baseDirectory: baseDir
        )

        // The web unit has a healthcheck with ${port}
        let webUnit = plan.service.units[2]
        XCTAssertEqual(
            webUnit.resolvedHealthcheck?.target,
            "http://localhost:8080/health"
        )
    }

    // MARK: - Port override via settings

    func testPortOverrideViaSetting() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.test-library",
            registry: registry,
            settings: ["data_path": "/srv/data", "port": "9999"],
            baseDirectory: baseDir
        )

        // The web unit is the one with a spec port
        let webUnit = plan.service.units[2]
        XCTAssertEqual(webUnit.port?.number, 9999)
        XCTAssertEqual(webUnit.port?.source, .settingOverride)
        // Environment should use overridden port
        XCTAssertEqual(webUnit.resolvedEnvironment["WEB_PORT"], "9999")
    }

    // MARK: - Default directory layout

    func testDefaultDirectoryLayout() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.test-library",
            registry: registry,
            settings: ["data_path": "/srv/data"],
            baseDirectory: baseDir
        )

        let layout = plan.service.directoryLayout
        let expectedRoot = baseDir
            .appendingPathComponent("Services")
            .appendingPathComponent("haven.capability.test-library")

        XCTAssertEqual(layout.serviceRoot, expectedRoot)
        XCTAssertEqual(layout.data, expectedRoot.appendingPathComponent("data"))
        XCTAssertEqual(layout.config, expectedRoot.appendingPathComponent("config"))
        XCTAssertEqual(layout.logs, expectedRoot.appendingPathComponent("logs"))
        XCTAssertEqual(layout.run, expectedRoot.appendingPathComponent("run"))
        XCTAssertEqual(layout.allDirectories.count, 5)
    }

    // MARK: - Error: missing capability

    func testMissingCapabilityThrows() {
        let registry = makeStandardRegistry()
        XCTAssertThrowsError(
            try Planner.planInstall(
                capabilityID: "haven.capability.nonexistent",
                registry: registry,
                baseDirectory: baseDir
            )
        ) { error in
            XCTAssertEqual(
                error as? PlanningError,
                .capabilityNotFound(id: "haven.capability.nonexistent")
            )
        }
    }

    // MARK: - Error: missing bundle

    func testMissingBundleThrows() {
        // Registry has the capability but no bundle that implements it
        let registry = SpecRegistry(
            capabilitiesByID: ["haven.capability.test-library": .testLibraryExample],
            bundlesByID: [:],
            runtimeUnitsByID: [:]
        )
        XCTAssertThrowsError(
            try Planner.planInstall(
                capabilityID: "haven.capability.test-library",
                registry: registry,
                baseDirectory: baseDir
            )
        ) { error in
            XCTAssertEqual(
                error as? PlanningError,
                .bundleNotFound(capabilityID: "haven.capability.test-library")
            )
        }
    }

    // MARK: - Error: missing runtime unit

    func testMissingRuntimeUnitThrows() {
        // Bundle references units that are not in the registry
        let registry = SpecRegistry(
            capabilitiesByID: ["haven.capability.test-library": .testLibraryExample],
            bundlesByID: ["haven.bundle.test-library-basic": .testLibraryBasicExample],
            runtimeUnitsByID: [:] // no units!
        )
        XCTAssertThrowsError(
            try Planner.planInstall(
                capabilityID: "haven.capability.test-library",
                registry: registry,
                settings: ["data_path": "/srv/data"],
                baseDirectory: baseDir
            )
        ) { error in
            XCTAssertEqual(
                error as? PlanningError,
                .runtimeUnitNotFound(
                    id: "haven.unit.test-db",
                    bundleID: "haven.bundle.test-library-basic"
                )
            )
        }
    }

    // MARK: - Error: required setting missing

    func testRequiredSettingMissingThrows() {
        // Make a bundle with a required field with no default
        let strictBundle = Bundle(
            id: "haven.bundle.strict",
            name: "Strict",
            capability: "haven.capability.test-library",
            runtimeUnits: [],
            settings: [
                SettingField(
                    key: "api_key",
                    label: "API Key",
                    fieldType: .string,
                    defaultValue: nil,
                    required: true
                )
            ]
        )
        let registry = SpecRegistry(
            capabilitiesByID: ["haven.capability.test-library": .testLibraryExample],
            bundlesByID: ["haven.bundle.strict": strictBundle],
            runtimeUnitsByID: [:]
        )
        XCTAssertThrowsError(
            try Planner.planInstall(
                capabilityID: "haven.capability.test-library",
                registry: registry,
                settings: [:], // no settings provided
                baseDirectory: baseDir
            )
        ) { error in
            XCTAssertEqual(
                error as? PlanningError,
                .requiredSettingMissing(key: "api_key", bundleID: "haven.bundle.strict")
            )
        }
    }

    // MARK: - Dependency cycle detection

    func testDependencyCycleThrows() {
        let unitA = RuntimeUnit(
            id: "unit.a", bundleID: "b", runtimeType: .native,
            installSource: "/bin/a", launchArguments: ["/bin/a"],
            dependsOn: ["unit.b"]
        )
        let unitB = RuntimeUnit(
            id: "unit.b", bundleID: "b", runtimeType: .native,
            installSource: "/bin/b", launchArguments: ["/bin/b"],
            dependsOn: ["unit.a"]
        )
        let bundle = Bundle(
            id: "b", name: "B",
            capability: "cap",
            runtimeUnits: ["unit.a", "unit.b"]
        )
        let cap = Capability(id: "cap", name: "Cap", version: "1.0.0")
        let registry = SpecRegistry(
            capabilitiesByID: ["cap": cap],
            bundlesByID: ["b": bundle],
            runtimeUnitsByID: ["unit.a": unitA, "unit.b": unitB]
        )

        XCTAssertThrowsError(
            try Planner.planInstall(
                capabilityID: "cap",
                registry: registry,
                baseDirectory: baseDir
            )
        ) { error in
            guard case .dependencyCycle(let unitIDs) = error as? PlanningError else {
                XCTFail("Expected dependencyCycle, got \(error)")
                return
            }
            // The cycle should contain both units
            XCTAssertTrue(unitIDs.contains("unit.a"), "Cycle should contain unit.a: \(unitIDs)")
            XCTAssertTrue(unitIDs.contains("unit.b"), "Cycle should contain unit.b: \(unitIDs)")
        }
    }

    // MARK: - Correct topological ordering

    func testTopologicalOrdering() throws {
        // C depends on B, B depends on A → order should be A, B, C
        let unitA = RuntimeUnit(
            id: "unit.a", bundleID: "b", runtimeType: .native,
            installSource: "/bin/a", launchArguments: ["/bin/a"]
        )
        let unitB = RuntimeUnit(
            id: "unit.b", bundleID: "b", runtimeType: .native,
            installSource: "/bin/b", launchArguments: ["/bin/b"],
            dependsOn: ["unit.a"]
        )
        let unitC = RuntimeUnit(
            id: "unit.c", bundleID: "b", runtimeType: .native,
            installSource: "/bin/c", launchArguments: ["/bin/c"],
            dependsOn: ["unit.b"]
        )
        let bundle = Bundle(
            id: "b", name: "B",
            capability: "cap",
            runtimeUnits: ["unit.c", "unit.a", "unit.b"] // intentionally out of order
        )
        let cap = Capability(id: "cap", name: "Cap", version: "1.0.0")
        let registry = SpecRegistry(
            capabilitiesByID: ["cap": cap],
            bundlesByID: ["b": bundle],
            runtimeUnitsByID: [
                "unit.a": unitA,
                "unit.b": unitB,
                "unit.c": unitC,
            ]
        )

        let plan = try Planner.planInstall(
            capabilityID: "cap",
            registry: registry,
            baseDirectory: baseDir
        )

        let order = plan.service.units.map(\.spec.id)
        XCTAssertEqual(order, ["unit.a", "unit.b", "unit.c"],
            "Units should be sorted dependencies-first, got: \(order)")
    }

    // MARK: - Settings: defaults used when user doesn't override

    func testDefaultSettingsUsedWhenNotOverridden() throws {
        let registry = makeStandardRegistry()
        // Only provide data_path (required). Port has a default of "8080".
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.test-library",
            registry: registry,
            settings: ["data_path": "/data/files"],
            baseDirectory: baseDir
        )

        XCTAssertEqual(plan.service.resolvedSettings["port"], "8080")
        XCTAssertEqual(plan.service.resolvedSettings["data_path"], "/data/files")
    }

    // MARK: - Template context contains directory paths

    func testTemplateContextContainsDirectoryPaths() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.test-library",
            registry: registry,
            settings: ["data_path": "/testdata"],
            baseDirectory: baseDir
        )

        // Check the web unit (units[2]) which has a port
        let ctx = plan.service.units[2].templateContext
        let layout = plan.service.directoryLayout

        XCTAssertEqual(ctx.values["data_dir"], layout.data.path)
        XCTAssertEqual(ctx.values["config_dir"], layout.config.path)
        XCTAssertEqual(ctx.values["logs_dir"], layout.logs.path)
        XCTAssertEqual(ctx.values["run_dir"], layout.run.path)
        XCTAssertEqual(ctx.values["service_root"], layout.serviceRoot.path)
        XCTAssertEqual(ctx.values["data_path"], "/testdata")
        XCTAssertEqual(ctx.values["port"], "8080")
    }

    // MARK: - Port conflict avoidance

    func testPortConflictAutoAssignsNextPort() throws {
        let registry = makeStandardRegistry()
        // Port 8080 is already in use by another installed service
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.test-library",
            registry: registry,
            settings: ["data_path": "/srv/data"],
            baseDirectory: baseDir,
            usedPorts: [8080]
        )

        let webUnit = plan.service.units[2]
        XCTAssertEqual(webUnit.port?.number, 8081)
        XCTAssertEqual(webUnit.port?.source, .autoAssigned)
        // Template expansion should use the reassigned port
        XCTAssertEqual(webUnit.resolvedEnvironment["WEB_PORT"], "8081")
        XCTAssertEqual(
            webUnit.resolvedHealthcheck?.target,
            "http://localhost:8081/health"
        )
    }

    func testNoConflictKeepsSpecPort() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.test-library",
            registry: registry,
            settings: ["data_path": "/srv/data"],
            baseDirectory: baseDir,
            usedPorts: [3000, 5000]
        )

        let webUnit = plan.service.units[2]
        XCTAssertEqual(webUnit.port?.number, 8080)
        XCTAssertEqual(webUnit.port?.source, .spec)
    }

    func testSettingOverrideConflictAutoAssigns() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.test-library",
            registry: registry,
            settings: ["data_path": "/srv/data", "port": "9999"],
            baseDirectory: baseDir,
            usedPorts: [9999]
        )

        let webUnit = plan.service.units[2]
        XCTAssertEqual(webUnit.port?.number, 10000)
        XCTAssertEqual(webUnit.port?.source, .autoAssigned)
    }

    func testWithinInstallConflictAutoAssigns() throws {
        // Two units that both want port 9000
        let unitA = RuntimeUnit(
            id: "unit.a", bundleID: "b", runtimeType: .native,
            installSource: "/bin/a",
            launchArguments: ["/bin/a"],
            port: 9000
        )
        let unitB = RuntimeUnit(
            id: "unit.b", bundleID: "b", runtimeType: .native,
            installSource: "/bin/b",
            launchArguments: ["/bin/b"],
            port: 9000
        )
        let bundle = Bundle(
            id: "b", name: "B",
            capability: "cap",
            runtimeUnits: ["unit.a", "unit.b"]
        )
        let cap = Capability(id: "cap", name: "Cap", version: "1.0.0")
        let registry = SpecRegistry(
            capabilitiesByID: ["cap": cap],
            bundlesByID: ["b": bundle],
            runtimeUnitsByID: ["unit.a": unitA, "unit.b": unitB]
        )

        let plan = try Planner.planInstall(
            capabilityID: "cap",
            registry: registry,
            baseDirectory: baseDir
        )

        // First unit keeps its spec port, second gets auto-assigned
        XCTAssertEqual(plan.service.units[0].port?.number, 9000)
        XCTAssertEqual(plan.service.units[0].port?.source, .spec)
        XCTAssertEqual(plan.service.units[1].port?.number, 9001)
        XCTAssertEqual(plan.service.units[1].port?.source, .autoAssigned)
    }
}
