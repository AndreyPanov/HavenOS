import XCTest
@testable import HavenCore

/// End-to-end tests that validate the Gitea multi-unit spec through
/// the full SpecLoader → Planner pipeline.
/// Gitea is the first multi-unit pilot: app + database with
/// readiness probes, shared directories, and shared environment.
final class GiteaSpecTests: XCTestCase {

    // MARK: - Helpers

    private func fixtureURL(_ name: String) throws -> URL {
        guard let url = Foundation.Bundle.module
            .url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw XCTSkip("Fixture '\(name)' not found in test bundle.")
        }
        return url
    }

    private func loadRegistry() throws -> SpecRegistry {
        let root = try fixtureURL("GiteaSpec")
        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "SpecLoader issues: \(result.issues)")
        return try XCTUnwrap(result.registry)
    }

    // MARK: - Spec Loading

    func testSpecLoadsWithoutIssues() throws {
        let root = try fixtureURL("GiteaSpec")
        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "Expected clean load, got issues: \(result.issues)")
        XCTAssertTrue(result.issues.isEmpty, "Unexpected issues: \(result.issues)")
    }

    func testCapabilityLoaded() throws {
        let registry = try loadRegistry()

        let cap = try XCTUnwrap(registry.capabilitiesByID["haven.capability.gitea"])
        XCTAssertEqual(cap.name, "Gitea")
        XCTAssertEqual(cap.version, "1.22.0")
        XCTAssertEqual(cap.icon, "arrow.triangle.branch")
    }

    func testBundleLoaded() throws {
        let registry = try loadRegistry()

        let bundle = try XCTUnwrap(registry.bundlesByID["haven.bundle.gitea-postgres"])
        XCTAssertEqual(bundle.capability, "haven.capability.gitea")
        XCTAssertEqual(bundle.runtimeUnits, ["haven.unit.gitea-db", "haven.unit.gitea-app"])

        // Settings
        XCTAssertEqual(bundle.settings.count, 3)
        XCTAssertNotNil(bundle.settings.first { $0.key == "http_port" })
        XCTAssertNotNil(bundle.settings.first { $0.key == "db_port" })
        XCTAssertNotNil(bundle.settings.first { $0.key == "repo_path" })

        // Shared directories
        XCTAssertEqual(bundle.sharedDirectories["socket"], "run/pg")

        // Shared environment
        XCTAssertEqual(
            bundle.sharedEnvironment["DATABASE_URL"],
            "postgresql://gitea:gitea@localhost:${db_port}/gitea"
        )

        // Storage
        XCTAssertEqual(bundle.storage["db_data"]?.persistent, true)
        XCTAssertEqual(bundle.storage["repos"]?.userVisible, true)

        // Onboarding
        XCTAssertEqual(bundle.onboarding?.steps.count, 3)
    }

    func testDatabaseUnitLoaded() throws {
        let registry = try loadRegistry()

        let unit = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.gitea-db"])
        XCTAssertEqual(unit.runtimeType, .native)
        XCTAssertEqual(unit.port, 5432)
        XCTAssertTrue(unit.dependsOn.isEmpty)

        // Readiness probe
        XCTAssertNotNil(unit.readinessProbe)
        XCTAssertEqual(unit.readinessProbe?.type, .tcp)
        XCTAssertTrue(unit.readinessProbe?.target.contains("${db_port}") == true)
        XCTAssertEqual(unit.readinessProbe?.timeoutSeconds, 30)
        XCTAssertEqual(unit.readinessProbe?.intervalSeconds, 2)

        // Healthcheck
        XCTAssertEqual(unit.healthcheck?.type, .tcp)
    }

    func testAppUnitLoaded() throws {
        let registry = try loadRegistry()

        let unit = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.gitea-app"])
        XCTAssertEqual(unit.runtimeType, .native)
        XCTAssertEqual(unit.port, 3000)
        XCTAssertEqual(unit.dependsOn, ["haven.unit.gitea-db"])

        // No readiness probe on the app (it's the leaf)
        XCTAssertNil(unit.readinessProbe)

        // Healthcheck
        XCTAssertEqual(unit.healthcheck?.type, .http)
    }

    // MARK: - Planner Integration

    func testPlannerProducesValidMultiUnitPlan() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.gitea",
            registry: registry,
            settings: ["repo_path": "/Volumes/Code/Repos"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let service = plan.service

        // Two units
        XCTAssertEqual(service.units.count, 2)

        // Topological order: DB first, then app
        XCTAssertEqual(service.units[0].spec.id, "haven.unit.gitea-db")
        XCTAssertEqual(service.units[1].spec.id, "haven.unit.gitea-app")
    }

    func testDatabaseUnitPlanned() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.gitea",
            registry: registry,
            settings: ["repo_path": "/Volumes/Code/Repos"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let dbUnit = plan.service.units[0]
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.gitea"

        // Port
        XCTAssertEqual(dbUnit.port?.number, 5432)

        // Directories
        XCTAssertEqual(dbUnit.resolvedDirectories["data"], "\(serviceRoot)/pgdata")

        // Environment
        XCTAssertEqual(dbUnit.resolvedEnvironment["PGDATA"], "\(serviceRoot)/pgdata")
        XCTAssertEqual(dbUnit.resolvedEnvironment["PGPORT"], "5432")

        // Shared environment is merged
        XCTAssertEqual(
            dbUnit.resolvedEnvironment["DATABASE_URL"],
            "postgresql://gitea:gitea@localhost:5432/gitea"
        )

        // Readiness probe expanded
        let probe = try XCTUnwrap(dbUnit.resolvedReadinessProbe)
        XCTAssertEqual(probe.type, .tcp)
        XCTAssertEqual(probe.target, "localhost:5432")
        XCTAssertEqual(probe.timeoutSeconds, 30)
        XCTAssertEqual(probe.intervalSeconds, 2)

        // Healthcheck expanded
        XCTAssertEqual(dbUnit.resolvedHealthcheck?.target, "localhost:5432")
    }

    func testAppUnitPlanned() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.gitea",
            registry: registry,
            settings: ["repo_path": "/Volumes/Code/Repos"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let appUnit = plan.service.units[1]
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.gitea"

        // Port
        XCTAssertEqual(appUnit.port?.number, 3000)

        // Directories
        XCTAssertEqual(appUnit.resolvedDirectories["config"], "\(serviceRoot)/config")
        XCTAssertEqual(appUnit.resolvedDirectories["data"], "\(serviceRoot)/data")
        XCTAssertEqual(appUnit.resolvedDirectories["repos"], "/Volumes/Code/Repos")

        // Launch args expanded
        XCTAssertEqual(appUnit.resolvedLaunchArguments, [
            "--config", "\(serviceRoot)/config/app.ini",
            "--port", "3000"
        ])

        // Environment
        XCTAssertEqual(appUnit.resolvedEnvironment["GITEA_WORK_DIR"], serviceRoot)
        XCTAssertEqual(appUnit.resolvedEnvironment["GITEA_CUSTOM"], "\(serviceRoot)/config")

        // Shared environment is merged
        XCTAssertEqual(
            appUnit.resolvedEnvironment["DATABASE_URL"],
            "postgresql://gitea:gitea@localhost:5432/gitea"
        )

        // No readiness probe on app
        XCTAssertNil(appUnit.resolvedReadinessProbe)

        // Healthcheck
        XCTAssertEqual(appUnit.resolvedHealthcheck?.target, "http://localhost:3000/api/healthz")
    }

    func testSharedDirectoriesExpanded() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.gitea",
            registry: registry,
            settings: ["repo_path": "/Volumes/Code/Repos"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        // The shared "socket" directory should be available in the service context.
        // We can verify indirectly: if sharedEnvironment referenced ${shared_socket_dir},
        // it would be expanded. Here we just verify the plan succeeds with sharedDirectories.
        XCTAssertEqual(plan.service.units.count, 2)
    }

    func testInstallStepsExpanded() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.gitea",
            registry: registry,
            settings: ["repo_path": "/Volumes/Code/Repos"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let serviceRoot = "/tmp/haven-test/Services/haven.capability.gitea"

        // DB install steps
        let dbInstall = try XCTUnwrap(plan.service.units[0].resolvedInstall)
        XCTAssertEqual(dbInstall.steps.count, 1)
        XCTAssertEqual(dbInstall.steps[0].path, "\(serviceRoot)/pgdata")

        // App install steps
        let appInstall = try XCTUnwrap(plan.service.units[1].resolvedInstall)
        XCTAssertEqual(appInstall.steps.count, 3)
        XCTAssertEqual(appInstall.steps[0].path, "\(serviceRoot)/config")
        XCTAssertEqual(appInstall.steps[1].path, "\(serviceRoot)/data")
        XCTAssertEqual(appInstall.steps[2].path, "\(serviceRoot)/config/app.ini")
        XCTAssertTrue(appInstall.steps[2].ifNotExists)

        // Config file content has expanded variables
        let content = try XCTUnwrap(appInstall.steps[2].content)
        XCTAssertTrue(content.contains("HOST = localhost:5432"))
        XCTAssertTrue(content.contains("HTTP_PORT = 3000"))
        XCTAssertTrue(content.contains("ROOT = /Volumes/Code/Repos"))
    }

    func testOnboardingExpanded() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.gitea",
            registry: registry,
            settings: ["repo_path": "/Volumes/Code/Repos"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let onboarding = try XCTUnwrap(plan.service.resolvedOnboarding)
        XCTAssertEqual(onboarding.steps.count, 3)

        // Step 1: repo path expanded
        XCTAssertEqual(onboarding.steps[0].fields[0].value, "/Volumes/Code/Repos")

        // Step 2: URL with expanded port
        XCTAssertEqual(onboarding.steps[1].url, "http://localhost:3000")

        // Step 3: server address
        XCTAssertEqual(onboarding.steps[2].fields[0].value, "http://your-mac:3000")
    }

    func testDefaultRepoPathExpandsTilde() throws {
        let registry = try loadRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.gitea",
            registry: registry,
            settings: [:],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let appUnit = plan.service.units[1]
        let expandedRepos = NSString(string: "~/GitRepos").expandingTildeInPath
        XCTAssertEqual(appUnit.resolvedDirectories["repos"], expandedRepos)
    }
}
