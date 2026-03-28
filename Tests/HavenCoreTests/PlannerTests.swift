import XCTest
import HavenCore

final class PlannerTests: XCTestCase {

    // MARK: - Helpers

    private let baseDir = URL(fileURLWithPath: "/tmp/haven-test")

    /// Build a registry from the standard music/navidrome examples.
    private func makeStandardRegistry() -> SpecRegistry {
        SpecRegistry(
            capabilitiesByID: [
                "haven.capability.music": .musicExample
            ],
            bundlesByID: [
                "haven.bundle.navidrome-single": .navidromeSingleExample
            ],
            runtimeUnitsByID: [
                "haven.unit.navidrome": .navidromeExample
            ]
        )
    }

    // MARK: - Successful planning

    func testSuccessfulPlanForMusic() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.music",
            registry: registry,
            settings: ["music_path": "/my/music"],
            baseDirectory: baseDir
        )

        let svc = plan.service

        // Capability
        XCTAssertEqual(svc.capability.id, "haven.capability.music")
        XCTAssertEqual(svc.capability.name, "Music")

        // Bundle
        XCTAssertEqual(svc.bundle.id, "haven.bundle.navidrome-single")

        // Resolved settings: user override + default
        XCTAssertEqual(svc.resolvedSettings["music_path"], "/my/music")
        XCTAssertEqual(svc.resolvedSettings["port"], "4533")

        // Directory layout
        XCTAssertTrue(svc.directoryLayout.serviceRoot.path.contains("haven.capability.music"))
        XCTAssertTrue(svc.directoryLayout.data.path.hasSuffix("data"))
        XCTAssertTrue(svc.directoryLayout.config.path.hasSuffix("config"))
        XCTAssertTrue(svc.directoryLayout.logs.path.hasSuffix("logs"))
        XCTAssertTrue(svc.directoryLayout.run.path.hasSuffix("run"))

        // Single runtime unit
        XCTAssertEqual(svc.units.count, 1)
        let unit = svc.units[0]
        XCTAssertEqual(unit.spec.id, "haven.unit.navidrome")

        // Port
        XCTAssertEqual(unit.port?.number, 4533)
        XCTAssertEqual(unit.port?.source, .spec)
    }

    // MARK: - Placeholder expansion

    func testPlaceholderExpansionInEnvironment() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.music",
            registry: registry,
            settings: ["music_path": "/srv/tunes"],
            baseDirectory: baseDir
        )

        let unit = plan.service.units[0]

        // Environment should have expanded ${music_path}
        XCTAssertEqual(unit.resolvedEnvironment["ND_MUSICFOLDER"], "/srv/tunes")

        // ${data_dir} should resolve to the planned data directory
        XCTAssertEqual(
            unit.resolvedEnvironment["ND_DATAFOLDER"],
            plan.service.directoryLayout.data.path
        )

        // ${port} should resolve to "4533"
        XCTAssertEqual(unit.resolvedEnvironment["ND_PORT"], "4533")
    }

    func testPlaceholderExpansionInLaunchArguments() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.music",
            registry: registry,
            settings: ["music_path": "/srv/tunes"],
            baseDirectory: baseDir
        )

        let unit = plan.service.units[0]
        let configDir = plan.service.directoryLayout.config.path

        // --configfile ${config_dir}/navidrome.toml should be expanded
        XCTAssertTrue(
            unit.resolvedLaunchArguments.contains("\(configDir)/navidrome.toml"),
            "Expected expanded config path, got: \(unit.resolvedLaunchArguments)"
        )
    }

    func testPlaceholderExpansionInHealthcheck() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.music",
            registry: registry,
            settings: ["music_path": "/srv/tunes"],
            baseDirectory: baseDir
        )

        let unit = plan.service.units[0]
        XCTAssertEqual(
            unit.resolvedHealthcheck?.target,
            "http://localhost:4533/ping"
        )
    }

    // MARK: - Port override via settings

    func testPortOverrideViaSetting() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.music",
            registry: registry,
            settings: ["music_path": "/srv/music", "port": "9999"],
            baseDirectory: baseDir
        )

        let unit = plan.service.units[0]
        XCTAssertEqual(unit.port?.number, 9999)
        XCTAssertEqual(unit.port?.source, .settingOverride)
        // Environment should use overridden port
        XCTAssertEqual(unit.resolvedEnvironment["ND_PORT"], "9999")
    }

    // MARK: - Default directory layout

    func testDefaultDirectoryLayout() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.music",
            registry: registry,
            settings: ["music_path": "/srv/music"],
            baseDirectory: baseDir
        )

        let layout = plan.service.directoryLayout
        let expectedRoot = baseDir
            .appendingPathComponent("Services")
            .appendingPathComponent("haven.capability.music")

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
            capabilitiesByID: ["haven.capability.music": .musicExample],
            bundlesByID: [:],
            runtimeUnitsByID: [:]
        )
        XCTAssertThrowsError(
            try Planner.planInstall(
                capabilityID: "haven.capability.music",
                registry: registry,
                baseDirectory: baseDir
            )
        ) { error in
            XCTAssertEqual(
                error as? PlanningError,
                .bundleNotFound(capabilityID: "haven.capability.music")
            )
        }
    }

    // MARK: - Error: missing runtime unit

    func testMissingRuntimeUnitThrows() {
        // Bundle references a unit that's not in the registry
        let registry = SpecRegistry(
            capabilitiesByID: ["haven.capability.music": .musicExample],
            bundlesByID: ["haven.bundle.navidrome-single": .navidromeSingleExample],
            runtimeUnitsByID: [:] // no units!
        )
        XCTAssertThrowsError(
            try Planner.planInstall(
                capabilityID: "haven.capability.music",
                registry: registry,
                settings: ["music_path": "/srv/music"],
                baseDirectory: baseDir
            )
        ) { error in
            XCTAssertEqual(
                error as? PlanningError,
                .runtimeUnitNotFound(
                    id: "haven.unit.navidrome",
                    bundleID: "haven.bundle.navidrome-single"
                )
            )
        }
    }

    // MARK: - Error: required setting missing

    func testRequiredSettingMissingThrows() {
        let registry = makeStandardRegistry()
        // music_path is required but not provided and has a default
        // — but let's make a bundle with a required field with no default
        let strictBundle = Bundle(
            id: "haven.bundle.strict",
            name: "Strict",
            capabilityIDs: ["haven.capability.music"],
            runtimeUnitIDs: [],
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
        let registry2 = SpecRegistry(
            capabilitiesByID: ["haven.capability.music": .musicExample],
            bundlesByID: ["haven.bundle.strict": strictBundle],
            runtimeUnitsByID: [:]
        )
        XCTAssertThrowsError(
            try Planner.planInstall(
                capabilityID: "haven.capability.music",
                registry: registry2,
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
            id: "unit.a", bundleID: "b", runtimeType: .binary,
            installSource: "/bin/a", launchArguments: ["/bin/a"],
            dependsOn: ["unit.b"]
        )
        let unitB = RuntimeUnit(
            id: "unit.b", bundleID: "b", runtimeType: .binary,
            installSource: "/bin/b", launchArguments: ["/bin/b"],
            dependsOn: ["unit.a"]
        )
        let bundle = Bundle(
            id: "b", name: "B",
            capabilityIDs: ["cap"],
            runtimeUnitIDs: ["unit.a", "unit.b"]
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
            id: "unit.a", bundleID: "b", runtimeType: .binary,
            installSource: "/bin/a", launchArguments: ["/bin/a"]
        )
        let unitB = RuntimeUnit(
            id: "unit.b", bundleID: "b", runtimeType: .binary,
            installSource: "/bin/b", launchArguments: ["/bin/b"],
            dependsOn: ["unit.a"]
        )
        let unitC = RuntimeUnit(
            id: "unit.c", bundleID: "b", runtimeType: .binary,
            installSource: "/bin/c", launchArguments: ["/bin/c"],
            dependsOn: ["unit.b"]
        )
        let bundle = Bundle(
            id: "b", name: "B",
            capabilityIDs: ["cap"],
            runtimeUnitIDs: ["unit.c", "unit.a", "unit.b"] // intentionally out of order
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
        // Only provide music_path (required). Port has a default of "4533".
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.music",
            registry: registry,
            settings: ["music_path": "/data/songs"],
            baseDirectory: baseDir
        )

        XCTAssertEqual(plan.service.resolvedSettings["port"], "4533")
        XCTAssertEqual(plan.service.resolvedSettings["music_path"], "/data/songs")
    }

    // MARK: - Template context contains directory paths

    func testTemplateContextContainsDirectoryPaths() throws {
        let registry = makeStandardRegistry()
        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.music",
            registry: registry,
            settings: ["music_path": "/music"],
            baseDirectory: baseDir
        )

        let ctx = plan.service.units[0].templateContext
        let layout = plan.service.directoryLayout

        XCTAssertEqual(ctx.values["data_dir"], layout.data.path)
        XCTAssertEqual(ctx.values["config_dir"], layout.config.path)
        XCTAssertEqual(ctx.values["logs_dir"], layout.logs.path)
        XCTAssertEqual(ctx.values["run_dir"], layout.run.path)
        XCTAssertEqual(ctx.values["service_root"], layout.serviceRoot.path)
        XCTAssertEqual(ctx.values["music_path"], "/music")
        XCTAssertEqual(ctx.values["port"], "4533")
    }
}
