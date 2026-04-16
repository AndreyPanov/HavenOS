import XCTest
@testable import HavenCore

/// End-to-end tests that validate the Kavita spec through
/// the full SpecLoader → Planner pipeline.
final class KavitaSpecTests: XCTestCase {

    // MARK: - Helpers

    private func fixtureURL(_ name: String) throws -> URL {
        guard let url = Foundation.Bundle.module
            .url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw XCTSkip("Fixture '\(name)' not found in test bundle.")
        }
        return url
    }

    private func loadRegistry() throws -> SpecRegistry {
        let root = try fixtureURL("KavitaSpec")
        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "SpecLoader issues: \(result.issues)")
        return try XCTUnwrap(result.registry)
    }

    // MARK: - Spec Loading

    func testSpecLoadsWithoutIssues() throws {
        let root = try fixtureURL("KavitaSpec")
        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "Expected clean load, got issues: \(result.issues)")
        XCTAssertTrue(result.issues.isEmpty, "Unexpected issues: \(result.issues)")
    }

    func testCapabilityLoaded() throws {
        let registry = try loadRegistry()

        let cap = try XCTUnwrap(registry.capabilitiesByID["haven.capability.kavita"])
        XCTAssertEqual(cap.name, "Kavita")
        XCTAssertEqual(cap.version, "0.8.9.1")
        XCTAssertEqual(cap.icon, "books.vertical")
    }

    func testBundleLoaded() throws {
        let registry = try loadRegistry()

        let bundle = try XCTUnwrap(registry.bundlesByID["haven.bundle.kavita-basic"])
        XCTAssertEqual(bundle.capability, "haven.capability.kavita")
        XCTAssertEqual(bundle.runtimeUnits, ["haven.unit.kavita"])

        // Settings
        XCTAssertEqual(bundle.settings.count, 2)
        let libSetting = try XCTUnwrap(bundle.settings.first { $0.key == "library_path" })
        XCTAssertEqual(libSetting.fieldType, .path)
        XCTAssertTrue(libSetting.required)
        XCTAssertEqual(libSetting.defaultValue, "~/Books")

        // Storage
        XCTAssertEqual(bundle.storage["config"]?.persistent, true)
        XCTAssertEqual(bundle.storage["config"]?.userVisible, false)
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

        let unit = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.kavita"])
        XCTAssertEqual(unit.runtimeType, .native)
        XCTAssertEqual(unit.port, 5000)

        // Artifact
        XCTAssertEqual(unit.artifact?.type, .githubRelease)
        XCTAssertEqual(unit.artifact?.repo, "Kareadita/Kavita")
        XCTAssertEqual(unit.artifact?.version, "v0.8.9.1")
        XCTAssertEqual(unit.artifact?.assets.count, 3)
        XCTAssertTrue(unit.artifact?.archive?.stripFirstDirectory == true)

        // Entrypoint
        XCTAssertEqual(unit.entrypoint?.command, "Kavita")

        // Directories
        XCTAssertEqual(unit.directories["config"], "config")
        XCTAssertEqual(unit.directories["content"], "${library_path}")

        // Install steps: mkdir×2 + generateSecret + writeFile + chmod
        XCTAssertEqual(unit.install?.steps.count, 5)
        XCTAssertEqual(unit.install?.steps[0].action, .mkdir)
        XCTAssertEqual(unit.install?.steps[1].action, .mkdir)
        XCTAssertEqual(unit.install?.steps[2].action, .generateSecret)
        XCTAssertEqual(unit.install?.steps[2].path, "token_key")
        XCTAssertEqual(unit.install?.steps[3].action, .writeFile)
        XCTAssertEqual(unit.install?.steps[4].action, .chmod)
        XCTAssertEqual(unit.install?.steps[4].mode, "600")

        // No dependencies
        XCTAssertTrue(unit.dependencies.isEmpty)

        // Healthcheck
        XCTAssertEqual(unit.healthcheck?.type, .http)
        XCTAssertTrue(unit.healthcheck?.target.contains("/api/health") == true)
    }

    // MARK: - Planner Integration

    func testPlannerProducesValidPlan() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.kavita",
            registry: registry,
            settings: ["library_path": "/Volumes/Books"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let service = plan.service
        XCTAssertEqual(service.units.count, 1)

        let planned = service.units[0]
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.kavita"

        // Port
        XCTAssertEqual(planned.port?.number, 5000)

        // Directories resolved
        XCTAssertEqual(planned.resolvedDirectories["config"], "\(serviceRoot)/config")
        XCTAssertEqual(planned.resolvedDirectories["content"], "/Volumes/Books")

        // Healthcheck expanded
        XCTAssertEqual(planned.resolvedHealthcheck?.target, "http://localhost:5000/api/health")
    }

    func testInstallStepsExpanded() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.kavita",
            registry: registry,
            settings: ["library_path": "/Volumes/Books"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let install = try XCTUnwrap(plan.service.units[0].resolvedInstall)
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.kavita"

        // mkdir steps expanded
        XCTAssertEqual(install.steps[0].path, "\(serviceRoot)/config")
        XCTAssertEqual(install.steps[1].path, "/Volumes/Books")

        // generateSecret keeps variable name
        XCTAssertEqual(install.steps[2].action, .generateSecret)
        XCTAssertEqual(install.steps[2].path, "token_key")
        XCTAssertEqual(install.steps[2].content, "64")

        // writeFile has expanded path; content has ${token_key} (runtime) + expanded ${port}
        XCTAssertEqual(install.steps[3].path, "\(serviceRoot)/config/appsettings.json")
        let content = try XCTUnwrap(install.steps[3].content)
        XCTAssertTrue(content.contains("\"TokenKey\": \"${token_key}\""))
        XCTAssertTrue(content.contains("\"Port\": 5000"))

        // chmod expanded
        XCTAssertEqual(install.steps[4].path, "\(serviceRoot)/config/appsettings.json")
        XCTAssertEqual(install.steps[4].mode, "600")
    }

    func testDefaultLibraryPathExpandsTilde() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.kavita",
            registry: registry,
            settings: [:],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let planned = plan.service.units[0]
        let expandedBooks = NSString(string: "~/Books").expandingTildeInPath
        XCTAssertEqual(planned.resolvedDirectories["content"], expandedBooks)
    }

    func testOnboardingExpanded() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.kavita",
            registry: registry,
            settings: ["library_path": "/Volumes/Books"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let onboarding = try XCTUnwrap(plan.service.resolvedOnboarding)
        XCTAssertEqual(onboarding.steps.count, 3)

        // Step 1: library folder field expanded
        XCTAssertEqual(onboarding.steps[0].fields[0].value, "/Volumes/Books")

        // Step 2: action with expanded port
        XCTAssertEqual(onboarding.steps[1].url, "http://localhost:5000")

        // Step 3: server address
        XCTAssertEqual(onboarding.steps[2].fields[0].value, "http://your-mac:5000")
    }
}
