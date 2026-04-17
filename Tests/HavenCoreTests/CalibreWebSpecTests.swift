import XCTest
@testable import HavenCore

/// End-to-end tests that validate the Calibre-Web spec through
/// the full SpecLoader → Planner pipeline.
/// Calibre-Web is the first Python runtime pilot service.
final class CalibreWebSpecTests: XCTestCase {

    // MARK: - Helpers

    private func fixtureURL(_ name: String) throws -> URL {
        guard let url = Foundation.Bundle.module
            .url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw XCTSkip("Fixture '\(name)' not found in test bundle.")
        }
        return url
    }

    private func loadRegistry() throws -> SpecRegistry {
        let root = try fixtureURL("CalibreWebSpec")
        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "SpecLoader issues: \(result.issues)")
        return try XCTUnwrap(result.registry)
    }

    // MARK: - Spec Loading

    func testSpecLoadsWithoutIssues() throws {
        let root = try fixtureURL("CalibreWebSpec")
        let result = SpecLoader.load(from: root)
        // iconImage is a local file that won't exist in test bundle — filter those warnings
        let realIssues = result.issues.filter { $0.severity == .error }
        XCTAssertTrue(realIssues.isEmpty, "Unexpected errors: \(realIssues)")
    }

    func testCapabilityLoaded() throws {
        let registry = try loadRegistry()

        let cap = try XCTUnwrap(registry.capabilitiesByID["haven.capability.calibre-web"])
        XCTAssertEqual(cap.name, "Calibre-Web")
        XCTAssertEqual(cap.version, "0.6.26")
        XCTAssertEqual(cap.icon, "books.vertical")
        XCTAssertNotNil(cap.fullDescription)
        XCTAssertFalse(cap.screenshots.isEmpty)
    }

    func testBundleLoaded() throws {
        let registry = try loadRegistry()

        let bundle = try XCTUnwrap(registry.bundlesByID["haven.bundle.calibre-web-basic"])
        XCTAssertEqual(bundle.capability, "haven.capability.calibre-web")
        XCTAssertEqual(bundle.runtimeUnits, ["haven.unit.calibre-web"])

        // Settings
        XCTAssertEqual(bundle.settings.count, 2)
        let libSetting = try XCTUnwrap(bundle.settings.first { $0.key == "library_path" })
        XCTAssertEqual(libSetting.fieldType, .path)
        XCTAssertTrue(libSetting.required)
        XCTAssertEqual(libSetting.defaultValue, "~/CalibreLibrary")

        let portSetting = try XCTUnwrap(bundle.settings.first { $0.key == "port" })
        XCTAssertEqual(portSetting.fieldType, .integer)
        XCTAssertEqual(portSetting.defaultValue, "8083")

        // Storage
        XCTAssertEqual(bundle.storage["config"]?.persistent, true)
        XCTAssertEqual(bundle.storage["config"]?.userVisible, false)
        XCTAssertEqual(bundle.storage["data"]?.persistent, true)
        XCTAssertEqual(bundle.storage["content"]?.persistent, true)
        XCTAssertEqual(bundle.storage["content"]?.userVisible, true)

        // Onboarding
        XCTAssertEqual(bundle.onboarding?.steps.count, 3)
        XCTAssertEqual(bundle.onboarding?.steps[0].type, .info)
        XCTAssertEqual(bundle.onboarding?.steps[1].type, .credentials)
        XCTAssertEqual(bundle.onboarding?.steps[2].type, .action)
    }

    func testRuntimeUnitLoaded() throws {
        let registry = try loadRegistry()

        let unit = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.calibre-web"])
        XCTAssertEqual(unit.runtimeType, .python)
        XCTAssertEqual(unit.port, 8083)

        // Python config
        XCTAssertEqual(unit.python?.package, "calibreweb")
        XCTAssertEqual(unit.python?.version, "0.6.26")
        XCTAssertEqual(unit.python?.entrypoint.module, "calibreweb")
        XCTAssertEqual(unit.python?.entrypoint.args, ["-p", "${config_dir}/app.db"])

        // No artifact (Python-managed)
        XCTAssertNil(unit.artifact)

        // Directories
        XCTAssertEqual(unit.directories["config"], "config")
        XCTAssertEqual(unit.directories["data"], "data")
        XCTAssertEqual(unit.directories["logs"], "logs")
        XCTAssertEqual(unit.directories["content"], "${library_path}")

        // Install steps: 3 × mkdir
        XCTAssertEqual(unit.install?.steps.count, 3)
        XCTAssertTrue(unit.install?.steps.allSatisfy { $0.action == .mkdir } == true)

        // Dependencies (both optional)
        XCTAssertEqual(unit.dependencies.count, 2)
        XCTAssertEqual(unit.dependencies[0].id, "convert")
        XCTAssertFalse(unit.dependencies[0].required)
        XCTAssertEqual(unit.dependencies[1].id, "magick")
        XCTAssertFalse(unit.dependencies[1].required)

        // Healthcheck
        XCTAssertEqual(unit.healthcheck?.type, .http)
        XCTAssertTrue(unit.healthcheck?.target.contains("${port}") == true)
    }

    // MARK: - Planner Integration

    func testPlannerProducesValidPlan() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.calibre-web",
            registry: registry,
            settings: ["library_path": "/Volumes/Books/Calibre"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let service = plan.service
        XCTAssertEqual(service.units.count, 1)

        let planned = service.units[0]
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.calibre-web"

        // Port
        XCTAssertEqual(planned.port?.number, 8083)

        // Directories resolved
        XCTAssertEqual(planned.resolvedDirectories["config"], "\(serviceRoot)/config")
        XCTAssertEqual(planned.resolvedDirectories["data"], "\(serviceRoot)/data")
        XCTAssertEqual(planned.resolvedDirectories["logs"], "\(serviceRoot)/logs")
        XCTAssertEqual(planned.resolvedDirectories["content"], "/Volumes/Books/Calibre")

        // Healthcheck expanded
        XCTAssertEqual(planned.resolvedHealthcheck?.target, "http://localhost:8083/")

        // Launch arguments expanded
        XCTAssertEqual(planned.resolvedLaunchArguments, ["-p", "\(serviceRoot)/config/app.db"])

        // Environment expanded
        XCTAssertEqual(planned.resolvedEnvironment["CALIBRE_DBPATH"], "\(serviceRoot)/config")
    }

    func testInstallStepsExpanded() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.calibre-web",
            registry: registry,
            settings: ["library_path": "/Volumes/Books/Calibre"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let install = try XCTUnwrap(plan.service.units[0].resolvedInstall)
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.calibre-web"

        XCTAssertEqual(install.steps.count, 3)
        XCTAssertEqual(install.steps[0].path, "\(serviceRoot)/config")
        XCTAssertEqual(install.steps[1].path, "\(serviceRoot)/data")
        XCTAssertEqual(install.steps[2].path, "\(serviceRoot)/logs")
    }

    func testDefaultLibraryPathExpandsTilde() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.calibre-web",
            registry: registry,
            settings: [:],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let planned = plan.service.units[0]
        let expandedLib = NSString(string: "~/CalibreLibrary").expandingTildeInPath
        XCTAssertEqual(planned.resolvedDirectories["content"], expandedLib)
    }

    func testOnboardingExpanded() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.calibre-web",
            registry: registry,
            settings: ["library_path": "/Volumes/Books/Calibre"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let onboarding = try XCTUnwrap(plan.service.resolvedOnboarding)
        XCTAssertEqual(onboarding.steps.count, 3)

        // Credentials step
        XCTAssertEqual(onboarding.steps[1].fields[0].value, "admin")
        XCTAssertEqual(onboarding.steps[1].fields[1].value, "admin123")

        // Action step with expanded port and content_dir
        XCTAssertEqual(onboarding.steps[2].url, "http://localhost:8083")
        XCTAssertTrue(onboarding.steps[2].body.contains("/Volumes/Books/Calibre"))
    }
}
