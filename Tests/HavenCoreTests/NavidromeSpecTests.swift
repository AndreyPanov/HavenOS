import XCTest
@testable import HavenCore

/// End-to-end tests that validate the Navidrome pilot spec through
/// the full SpecLoader → Planner pipeline.
final class NavidromeSpecTests: XCTestCase {

    // MARK: - Helpers

    private func fixtureURL(_ name: String) throws -> URL {
        guard let url = Foundation.Bundle.module
            .url(forResource: name, withExtension: nil, subdirectory: "Fixtures") else {
            throw XCTSkip("Fixture '\(name)' not found in test bundle.")
        }
        return url
    }

    private func loadNavidromeRegistry() throws -> SpecRegistry {
        let root = try fixtureURL("NavidromeSpec")
        let result = SpecLoader.load(from: root)
        XCTAssertTrue(result.succeeded, "SpecLoader issues: \(result.issues)")
        return try XCTUnwrap(result.registry)
    }

    // MARK: - Spec Loading

    func testNavidromeSpecLoadsWithoutIssues() throws {
        let root = try fixtureURL("NavidromeSpec")
        let result = SpecLoader.load(from: root)

        XCTAssertTrue(result.succeeded, "Expected clean load, got issues: \(result.issues)")
        XCTAssertTrue(result.issues.isEmpty, "Unexpected issues: \(result.issues)")
    }

    func testCapabilityLoaded() throws {
        let registry = try loadNavidromeRegistry()

        let cap = try XCTUnwrap(registry.capabilitiesByID["haven.capability.navidrome"])
        XCTAssertEqual(cap.name, "Navidrome")
        XCTAssertEqual(cap.version, "0.53.3")
        XCTAssertEqual(cap.icon, "music.note.house")
        XCTAssertEqual(cap.notes, ["Music", "Streaming", "Subsonic"])
    }

    func testBundleLoaded() throws {
        let registry = try loadNavidromeRegistry()

        let bundle = try XCTUnwrap(registry.bundlesByID["haven.bundle.navidrome-basic"])
        XCTAssertEqual(bundle.capability, "haven.capability.navidrome")
        XCTAssertEqual(bundle.runtimeUnits, ["haven.unit.navidrome"])
        XCTAssertEqual(bundle.settings.count, 2)

        // Settings
        let portSetting = try XCTUnwrap(bundle.settings.first { $0.key == "port" })
        XCTAssertEqual(portSetting.fieldType, .integer)
        XCTAssertEqual(portSetting.defaultValue, "4533")

        let musicSetting = try XCTUnwrap(bundle.settings.first { $0.key == "music_path" })
        XCTAssertEqual(musicSetting.fieldType, .path)
        XCTAssertTrue(musicSetting.required)

        // Storage policies
        XCTAssertEqual(bundle.storage["data"]?.persistent, true)
        XCTAssertEqual(bundle.storage["data"]?.userVisible, false)
        XCTAssertEqual(bundle.storage["content"]?.persistent, true)
        XCTAssertEqual(bundle.storage["content"]?.userVisible, true)
        XCTAssertEqual(bundle.storage["cache"]?.persistent, false)

        // Onboarding
        XCTAssertNotNil(bundle.onboarding)
        XCTAssertEqual(bundle.onboarding?.steps.count, 2)
        XCTAssertEqual(bundle.onboarding?.steps[0].type, .info)
        XCTAssertEqual(bundle.onboarding?.steps[1].type, .action)
    }

    func testRuntimeUnitLoaded() throws {
        let registry = try loadNavidromeRegistry()

        let unit = try XCTUnwrap(registry.runtimeUnitsByID["haven.unit.navidrome"])
        XCTAssertEqual(unit.bundleID, "haven.bundle.navidrome-basic")
        XCTAssertEqual(unit.runtimeType, .native)
        XCTAssertEqual(unit.port, 4533)

        // Artifact
        XCTAssertNotNil(unit.artifact)
        XCTAssertEqual(unit.artifact?.type, .githubRelease)
        XCTAssertEqual(unit.artifact?.repo, "navidrome/navidrome")
        XCTAssertEqual(unit.artifact?.version, "v0.53.3")
        XCTAssertEqual(unit.artifact?.assets.count, 3)
        XCTAssertEqual(unit.artifact?.archive?.format, "tar.gz")

        // Entrypoint
        XCTAssertEqual(unit.entrypoint?.command, "navidrome")

        // Directories
        XCTAssertEqual(unit.directories["data"], "data")
        XCTAssertEqual(unit.directories["config"], "config")
        XCTAssertEqual(unit.directories["content"], "${music_path}")

        // Install steps
        XCTAssertNotNil(unit.install)
        XCTAssertEqual(unit.install?.steps.count, 8)
        XCTAssertEqual(unit.install?.steps[5].action, .generateSecret)
        XCTAssertEqual(unit.install?.steps[5].path, "session_key")
        XCTAssertEqual(unit.install?.steps[6].action, .writeFile)
        XCTAssertEqual(unit.install?.steps[7].action, .chmod)
        XCTAssertEqual(unit.install?.steps[7].mode, "600")

        // Dependencies
        XCTAssertEqual(unit.dependencies.count, 1)
        XCTAssertEqual(unit.dependencies[0].id, "ffmpeg")
        XCTAssertEqual(unit.dependencies[0].kind, .helperBinary)
        XCTAssertFalse(unit.dependencies[0].required)

        // Healthcheck
        XCTAssertNotNil(unit.healthcheck)
        XCTAssertEqual(unit.healthcheck?.type, .http)
    }

    // MARK: - Planner Integration

    func testPlannerProducesValidPlan() throws {
        let registry = try loadNavidromeRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.navidrome",
            registry: registry,
            settings: ["music_path": "/Volumes/Music"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let service = plan.service
        XCTAssertEqual(service.capability.id, "haven.capability.navidrome")
        XCTAssertEqual(service.bundle.id, "haven.bundle.navidrome-basic")
        XCTAssertEqual(service.units.count, 1)

        let planned = service.units[0]

        // Port
        XCTAssertEqual(planned.port?.number, 4533)

        // Template expansion in launch args
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.navidrome"
        XCTAssertEqual(planned.resolvedLaunchArguments, [
            "--configfile", "\(serviceRoot)/config/navidrome.toml"
        ])

        // Template expansion in environment
        XCTAssertEqual(planned.resolvedEnvironment["ND_DATAFOLDER"], "\(serviceRoot)/data")
        XCTAssertEqual(planned.resolvedEnvironment["ND_MUSICFOLDER"], "/Volumes/Music")
        XCTAssertEqual(planned.resolvedEnvironment["ND_PORT"], "4533")

        // Resolved directories
        XCTAssertEqual(planned.resolvedDirectories["data"], "\(serviceRoot)/data")
        XCTAssertEqual(planned.resolvedDirectories["config"], "\(serviceRoot)/config")
        XCTAssertEqual(planned.resolvedDirectories["content"], "/Volumes/Music")

        // Healthcheck expanded
        XCTAssertEqual(planned.resolvedHealthcheck?.target, "http://localhost:4533/ping")
    }

    func testInstallStepsAreExpanded() throws {
        let registry = try loadNavidromeRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.navidrome",
            registry: registry,
            settings: ["music_path": "/Volumes/Music"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let planned = plan.service.units[0]
        let install = try XCTUnwrap(planned.resolvedInstall)
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.navidrome"

        // mkdir steps have expanded paths
        XCTAssertEqual(install.steps[0].path, "\(serviceRoot)/data")
        XCTAssertEqual(install.steps[1].path, "\(serviceRoot)/config")
        XCTAssertEqual(install.steps[2].path, "\(serviceRoot)/logs")
        XCTAssertEqual(install.steps[3].path, "\(serviceRoot)/cache")
        XCTAssertEqual(install.steps[4].path, "/Volumes/Music")

        // generateSecret keeps variable name (not a path)
        XCTAssertEqual(install.steps[5].action, .generateSecret)
        XCTAssertEqual(install.steps[5].path, "session_key")

        // writeFile has expanded path; content still has ${session_key}
        // (generated at runtime by InstallStepExecutor)
        XCTAssertEqual(install.steps[6].path, "\(serviceRoot)/config/navidrome.toml")
        let content = try XCTUnwrap(install.steps[6].content)
        XCTAssertTrue(content.contains("MusicFolder = \"/Volumes/Music\""))
        XCTAssertTrue(content.contains("DataFolder = \"\(serviceRoot)/data\""))
        XCTAssertTrue(content.contains("Port = 4533"))
        // session_key is NOT expanded here — it's generated at runtime
        XCTAssertTrue(content.contains("${session_key}"))

        // chmod has expanded path
        XCTAssertEqual(install.steps[7].path, "\(serviceRoot)/config/navidrome.toml")
        XCTAssertEqual(install.steps[7].mode, "600")
    }

    func testOnboardingIsExpanded() throws {
        let registry = try loadNavidromeRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.navidrome",
            registry: registry,
            settings: ["music_path": "/Volumes/Music"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let onboarding = try XCTUnwrap(plan.service.resolvedOnboarding)
        XCTAssertEqual(onboarding.steps.count, 2)

        // Info step should have expanded music path
        XCTAssertTrue(onboarding.steps[0].body.contains("/Volumes/Music"))

        // Action step should have expanded port
        XCTAssertEqual(onboarding.steps[1].url, "http://localhost:4533")
    }

    func testDefaultMusicPathUsedWhenNotOverridden() throws {
        let registry = try loadNavidromeRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.navidrome",
            registry: registry,
            settings: [:],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let planned = plan.service.units[0]
        XCTAssertEqual(planned.resolvedEnvironment["ND_MUSICFOLDER"], "~/Music")
        XCTAssertEqual(planned.resolvedDirectories["content"], "~/Music")
    }
}
