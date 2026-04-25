import Testing
import Foundation
@testable import HavenAppKit
import HavenCore

/// Tests for the Jellyfin built-in spec and its integration with the Planner.
@Suite("Jellyfin Built-In Spec")
struct JellyfinSpecTests {

    // MARK: - Spec Structure

    @Test("Built-in catalog contains jellyfin entry")
    func catalogContainsJellyfin() {
        let (cap, bundle, units) = BuiltInCatalog.jellyfin
        #expect(cap.id == "haven.capability.jellyfin")
        #expect(bundle.id == "haven.bundle.jellyfin-basic")
        #expect(units.count == 1)
        #expect(units[0].id == "haven.unit.jellyfin")
    }

    @Test("Capability has correct metadata")
    func capabilityMetadata() {
        let (cap, _, _) = BuiltInCatalog.jellyfin
        #expect(cap.name == "Jellyfin")
        #expect(cap.version == "10.10.6")
        #expect(cap.icon == "film")
        #expect(cap.notes == ["Movies", "TV Shows", "Streaming"])
        #expect(cap.fullDescription?.contains("free software media system") == true)
    }

    @Test("Bundle references correct capability and unit")
    func bundleReferences() {
        let (_, bundle, _) = BuiltInCatalog.jellyfin
        #expect(bundle.capability == "haven.capability.jellyfin")
        #expect(bundle.runtimeUnits == ["haven.unit.jellyfin"])
    }

    @Test("Bundle has correct settings")
    func bundleSettings() {
        let (_, bundle, _) = BuiltInCatalog.jellyfin
        #expect(bundle.settings.count == 2)

        let moviesSetting = bundle.settings.first { $0.key == "movies_path" }
        #expect(moviesSetting != nil)
        #expect(moviesSetting?.fieldType == .path)
        #expect(moviesSetting?.defaultValue == "~/Movies")
        #expect(moviesSetting?.required == true)

        let portSetting = bundle.settings.first { $0.key == "port" }
        #expect(portSetting != nil)
        #expect(portSetting?.fieldType == .integer)
        #expect(portSetting?.defaultValue == "8096")
    }

    @Test("Bundle has correct storage policies")
    func bundleStorage() {
        let (_, bundle, _) = BuiltInCatalog.jellyfin
        #expect(bundle.storage["data"]?.persistent == true)
        #expect(bundle.storage["data"]?.userVisible == false)
        #expect(bundle.storage["config"]?.persistent == true)
        #expect(bundle.storage["config"]?.userVisible == false)
        #expect(bundle.storage["cache"]?.persistent == false)
        #expect(bundle.storage["logs"]?.persistent == false)
        #expect(bundle.storage["content"]?.persistent == true)
        #expect(bundle.storage["content"]?.userVisible == true)
    }

    @Test("Bundle has 3-step onboarding")
    func bundleOnboarding() {
        let (_, bundle, _) = BuiltInCatalog.jellyfin
        let steps = bundle.onboarding?.steps ?? []
        #expect(steps.count == 3)
        #expect(steps[0].type == .info)
        #expect(steps[0].title == "Your movie server is ready")
        #expect(steps[1].type == .info)
        #expect(steps[1].fields.count == 1)
        #expect(steps[2].type == .info)
        #expect(steps[2].fields.count == 1)
    }

    @Test("Runtime unit is native with correct port")
    func runtimeUnit() {
        let (_, _, units) = BuiltInCatalog.jellyfin
        let unit = units[0]
        #expect(unit.runtimeType == .native)
        #expect(unit.port == 8096)
        #expect(unit.bundleID == "haven.bundle.jellyfin-basic")
    }

    @Test("Runtime unit has GitHub Release artifact")
    func artifact() {
        let (_, _, units) = BuiltInCatalog.jellyfin
        let artifact = units[0].artifact
        #expect(artifact?.type == .githubRelease)
        #expect(artifact?.repo == "jellyfin/jellyfin")
        #expect(artifact?.version == "v10.10.6")
        #expect(artifact?.assets.count == 3)
        #expect(artifact?.archive?.format == "tar.gz")
        #expect(artifact?.archive?.stripFirstDirectory == true)
    }

    @Test("Runtime unit has correct entrypoint")
    func entrypoint() {
        let (_, _, units) = BuiltInCatalog.jellyfin
        #expect(units[0].entrypoint?.command == "jellyfin")
    }

    @Test("Runtime unit has 5 directory mappings")
    func directories() {
        let (_, _, units) = BuiltInCatalog.jellyfin
        let dirs = units[0].directories
        #expect(dirs.count == 5)
        #expect(dirs["data"] == "data")
        #expect(dirs["config"] == "config")
        #expect(dirs["cache"] == "cache")
        #expect(dirs["logs"] == "logs")
        #expect(dirs["content"] == "${movies_path}")
    }

    @Test("Runtime unit has 5 mkdir install steps")
    func installSteps() {
        let (_, _, units) = BuiltInCatalog.jellyfin
        let steps = units[0].install?.steps ?? []
        #expect(steps.count == 5)
        for step in steps {
            #expect(step.action == .mkdir)
        }
    }

    @Test("Runtime unit has optional ffmpeg dependency")
    func dependencies() {
        let (_, _, units) = BuiltInCatalog.jellyfin
        #expect(units[0].dependencies.count == 1)
        let dep = units[0].dependencies[0]
        #expect(dep.id == "ffmpeg")
        #expect(dep.kind == .helperBinary)
        #expect(dep.required == false)
    }

    @Test("Runtime unit has HTTP healthcheck")
    func healthcheck() {
        let (_, _, units) = BuiltInCatalog.jellyfin
        let hc = units[0].healthcheck
        #expect(hc?.type == .http)
        #expect(hc?.target.contains("/System/Ping") == true)
    }

    @Test("Launch arguments reference template variables")
    func launchArguments() {
        let (_, _, units) = BuiltInCatalog.jellyfin
        let args = units[0].launchArguments
        #expect(args.contains("--datadir"))
        #expect(args.contains("${data_dir}"))
        #expect(args.contains("--configdir"))
        #expect(args.contains("${config_dir}"))
        #expect(args.contains("--cachedir"))
        #expect(args.contains("${cache_dir}"))
        #expect(args.contains("--logdir"))
        #expect(args.contains("${logs_dir}"))
    }

    // MARK: - Registry Construction

    @Test("makeRegistry includes Jellyfin spec")
    func registryIncludesJellyfin() {
        let registry = BuiltInCatalog.makeRegistry()
        #expect(registry.capabilitiesByID["haven.capability.jellyfin"] != nil)
        #expect(registry.bundlesByID["haven.bundle.jellyfin-basic"] != nil)
        #expect(registry.runtimeUnitsByID["haven.unit.jellyfin"] != nil)
    }

    @Test("makeCatalogEntries includes Jellyfin")
    func catalogEntriesIncludeJellyfin() {
        let entries = BuiltInCatalog.makeCatalogEntries()
        let jellyfin = entries.first { $0.capability.id == "haven.capability.jellyfin" }
        #expect(jellyfin != nil)
        #expect(jellyfin?.metadata.icon == "film")
    }

    // MARK: - Planner Integration

    @Test("Planner produces valid plan with custom movies path")
    func plannerCustomPath() throws {
        let registry = BuiltInCatalog.makeRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.jellyfin",
            registry: registry,
            settings: ["movies_path": "/Volumes/Media/Movies"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let service = plan.service
        #expect(service.capability.id == "haven.capability.jellyfin")
        #expect(service.units.count == 1)

        let planned = service.units[0]
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.jellyfin"

        // Port
        #expect(planned.port?.number == 8096)

        // Directories resolved
        #expect(planned.resolvedDirectories["data"] == "\(serviceRoot)/data")
        #expect(planned.resolvedDirectories["config"] == "\(serviceRoot)/config")
        #expect(planned.resolvedDirectories["cache"] == "\(serviceRoot)/cache")
        #expect(planned.resolvedDirectories["logs"] == "\(serviceRoot)/logs")
        #expect(planned.resolvedDirectories["content"] == "/Volumes/Media/Movies")

        // Healthcheck expanded
        #expect(planned.resolvedHealthcheck?.target == "http://localhost:8096/System/Ping")
    }

    @Test("Planner expands install steps correctly")
    func plannerInstallSteps() throws {
        let registry = BuiltInCatalog.makeRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.jellyfin",
            registry: registry,
            settings: ["movies_path": "/Volumes/Media"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let install = try #require(plan.service.units[0].resolvedInstall)
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.jellyfin"

        #expect(install.steps.count == 5)
        #expect(install.steps[0].path == "\(serviceRoot)/data")
        #expect(install.steps[1].path == "\(serviceRoot)/config")
        #expect(install.steps[2].path == "\(serviceRoot)/logs")
        #expect(install.steps[3].path == "\(serviceRoot)/cache")
        #expect(install.steps[4].path == "/Volumes/Media")
    }

    @Test("Planner expands launch arguments")
    func plannerLaunchArgs() throws {
        let registry = BuiltInCatalog.makeRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.jellyfin",
            registry: registry,
            settings: ["movies_path": "/Movies"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let planned = plan.service.units[0]
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.jellyfin"

        #expect(planned.resolvedLaunchArguments.contains("\(serviceRoot)/data"))
        #expect(planned.resolvedLaunchArguments.contains("\(serviceRoot)/config"))
        #expect(planned.resolvedLaunchArguments.contains("\(serviceRoot)/cache"))
        #expect(planned.resolvedLaunchArguments.contains("\(serviceRoot)/logs"))
    }

    @Test("Default movies path expands tilde")
    func defaultPathExpandsTilde() throws {
        let registry = BuiltInCatalog.makeRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.jellyfin",
            registry: registry,
            settings: [:],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let planned = plan.service.units[0]
        let expandedMovies = NSString(string: "~/Movies").expandingTildeInPath
        #expect(planned.resolvedDirectories["content"] == expandedMovies)
    }

    @Test("Onboarding steps are expanded")
    func onboardingExpanded() throws {
        let registry = BuiltInCatalog.makeRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.jellyfin",
            registry: registry,
            settings: ["movies_path": "/Volumes/Media"],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let onboarding = try #require(plan.service.resolvedOnboarding)
        #expect(onboarding.steps.count == 3)

        // Step 2: movies folder field expanded
        #expect(onboarding.steps[1].fields[0].value == "/Volumes/Media")

        // Step 3: server address
        #expect(onboarding.steps[2].fields[0].value == "http://your-mac:8096")
    }

    @Test("Environment variables expanded")
    func environmentExpanded() throws {
        let registry = BuiltInCatalog.makeRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.jellyfin",
            registry: registry,
            settings: [:],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let planned = plan.service.units[0]
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.jellyfin"
        #expect(planned.resolvedEnvironment["JELLYFIN_LOG_DIR"] == "\(serviceRoot)/logs")
    }
}
