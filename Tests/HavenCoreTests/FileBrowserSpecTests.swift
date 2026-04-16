import XCTest
@testable import HavenCore

/// End-to-end tests that validate the File Browser spec through
/// the full SpecLoader → Planner pipeline.
final class FileBrowserSpecTests: XCTestCase {

    // MARK: - Helpers

    private func fixtureURL(_ name: String) throws -> URL {
        guard let url = Foundation.Bundle.module
            .url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw XCTSkip("Fixture '\(name)' not found in test bundle.")
        }
        return url
    }

    private func loadRegistry() throws -> SpecRegistry {
        let root = try fixtureURL("FileBrowserSpec")
        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "SpecLoader issues: \(result.issues)")
        return try XCTUnwrap(result.registry)
    }

    // MARK: - Spec Loading

    func testSpecLoadsWithoutIssues() throws {
        let root = try fixtureURL("FileBrowserSpec")
        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "Expected clean load, got issues: \(result.issues)")
        XCTAssertTrue(result.issues.isEmpty, "Unexpected issues: \(result.issues)")
    }

    func testCapabilityLoaded() throws {
        let registry = try loadRegistry()

        let cap = try XCTUnwrap(registry.capabilitiesByID["haven.capability.filebrowser"])
        XCTAssertEqual(cap.name, "File Browser")
        XCTAssertEqual(cap.version, "2.63.2")
        XCTAssertEqual(cap.icon, "folder")
    }

    func testBundleLoaded() throws {
        let registry = try loadRegistry()

        let bundle = try XCTUnwrap(registry.bundlesByID["haven.bundle.filebrowser-basic"])
        XCTAssertEqual(bundle.capability, "haven.capability.filebrowser")
        XCTAssertEqual(bundle.runtimeUnits, ["haven.unit.filebrowser"])

        // Settings
        XCTAssertEqual(bundle.settings.count, 2)
        let rootSetting = try XCTUnwrap(bundle.settings.first { $0.key == "root_path" })
        XCTAssertEqual(rootSetting.fieldType, .path)
        XCTAssertTrue(rootSetting.required)
        XCTAssertEqual(rootSetting.defaultValue, "~/Documents")

        let portSetting = try XCTUnwrap(bundle.settings.first { $0.key == "port" })
        XCTAssertEqual(portSetting.fieldType, .integer)
        XCTAssertEqual(portSetting.defaultValue, "8080")

        // Storage
        XCTAssertEqual(bundle.storage["data"]?.persistent, true)
        XCTAssertEqual(bundle.storage["data"]?.userVisible, false)
        XCTAssertEqual(bundle.storage["content"]?.persistent, true)
        XCTAssertEqual(bundle.storage["content"]?.userVisible, true)

        // Onboarding
        XCTAssertEqual(bundle.onboarding?.steps.count, 3)
        XCTAssertEqual(bundle.onboarding?.steps[0].type, .info)
        XCTAssertEqual(bundle.onboarding?.steps[1].type, .action)
        XCTAssertEqual(bundle.onboarding?.steps[2].type, .info)
    }

    func testRuntimeUnitLoaded() throws {
        let registry = try loadRegistry()

        let unit = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.filebrowser"])
        XCTAssertEqual(unit.runtimeType, .native)
        XCTAssertEqual(unit.port, 8080)

        // Artifact
        XCTAssertEqual(unit.artifact?.type, .githubRelease)
        XCTAssertEqual(unit.artifact?.repo, "filebrowser/filebrowser")
        XCTAssertEqual(unit.artifact?.version, "v2.63.2")
        XCTAssertEqual(unit.artifact?.assets.count, 3)

        // Entrypoint
        XCTAssertEqual(unit.entrypoint?.command, "filebrowser")

        // Directories
        XCTAssertEqual(unit.directories["data"], "data")
        XCTAssertEqual(unit.directories["content"], "${root_path}")

        // Install steps — minimal: just 2 mkdirs
        XCTAssertEqual(unit.install?.steps.count, 2)
        XCTAssertEqual(unit.install?.steps[0].action, .mkdir)
        XCTAssertEqual(unit.install?.steps[1].action, .mkdir)

        // No dependencies
        XCTAssertTrue(unit.dependencies.isEmpty)

        // Healthcheck
        XCTAssertEqual(unit.healthcheck?.type, .http)
        XCTAssertTrue(unit.healthcheck?.target.contains("/health") == true)
    }

    // MARK: - Planner Integration

    func testPlannerProducesValidPlan() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.filebrowser",
            registry: registry,
            settings: ["root_path": "/Volumes/Files"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let service = plan.service
        XCTAssertEqual(service.units.count, 1)

        let planned = service.units[0]
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.filebrowser"

        // Port assigned
        XCTAssertEqual(planned.port?.number, 8080)

        // Launch args expanded
        XCTAssertEqual(planned.resolvedLaunchArguments, [
            "--port", "8080",
            "--root", "/Volumes/Files",
            "--database", "\(serviceRoot)/data/filebrowser.db",
            "--noauth"
        ])

        // Directories resolved
        XCTAssertEqual(planned.resolvedDirectories["data"], "\(serviceRoot)/data")
        XCTAssertEqual(planned.resolvedDirectories["content"], "/Volumes/Files")

        // Healthcheck expanded
        XCTAssertEqual(planned.resolvedHealthcheck?.target, "http://localhost:8080/health")
    }

    func testInstallStepsExpanded() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.filebrowser",
            registry: registry,
            settings: ["root_path": "/Volumes/Files"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let install = try XCTUnwrap(plan.service.units[0].resolvedInstall)
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.filebrowser"

        XCTAssertEqual(install.steps.count, 2)
        XCTAssertEqual(install.steps[0].path, "\(serviceRoot)/data")
        XCTAssertEqual(install.steps[1].path, "/Volumes/Files")
    }

    func testDefaultRootPathExpandsTilde() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.filebrowser",
            registry: registry,
            settings: [:],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let planned = plan.service.units[0]
        let expandedDocs = NSString(string: "~/Documents").expandingTildeInPath
        XCTAssertEqual(planned.resolvedDirectories["content"], expandedDocs)
    }

    func testOnboardingExpanded() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.filebrowser",
            registry: registry,
            settings: ["root_path": "/Volumes/Files"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let onboarding = try XCTUnwrap(plan.service.resolvedOnboarding)
        XCTAssertEqual(onboarding.steps.count, 3)
        XCTAssertEqual(onboarding.steps[1].url, "http://localhost:8080")
        XCTAssertEqual(onboarding.steps[2].fields[0].value, "http://your-mac:8080")
    }
}
