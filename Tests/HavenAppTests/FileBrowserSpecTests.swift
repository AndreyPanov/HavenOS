import Testing
import Foundation
@testable import HavenAppKit
import HavenCore

@Suite("File Browser Built-In Spec")
struct FileBrowserSpecTests {

    @Test("Built-in catalog contains File Browser entry")
    func catalogContainsFileBrowser() {
        let (capability, bundle, units) = BuiltInCatalog.filebrowser

        #expect(capability.id == "haven.capability.filebrowser")
        #expect(bundle.id == "haven.bundle.filebrowser-basic")
        #expect(units.count == 1)
        #expect(units[0].id == "haven.unit.filebrowser")
    }

    @Test("Bundle requires managed credentials")
    func bundleRequiresManagedCredentials() {
        let (_, bundle, _) = BuiltInCatalog.filebrowser

        let username = bundle.settings.first { $0.key == "files_username" }
        let password = bundle.settings.first { $0.key == "files_password" }

        #expect(username?.defaultValue == "haven")
        #expect(username?.required == true)
        #expect(username?.sensitive == true)
        #expect(password?.defaultValue == nil)
        #expect(password?.required == true)
        #expect(password?.sensitive == true)
    }

    @Test("Runtime uses authentication, not noauth")
    func runtimeUsesAuthentication() {
        let (_, _, units) = BuiltInCatalog.filebrowser
        let args = units[0].launchArguments

        #expect(!args.contains("--noauth"))
        #expect(!args.contains("--username"))
        #expect(!args.contains("--password"))
        #expect(!args.contains("${files_username}"))
        #expect(!args.contains("${files_password}"))
        #expect(args.contains("--disableExec"))
    }

    @Test("Install steps create secure File Browser database")
    func installStepsCreateSecureDatabase() {
        let (_, _, units) = BuiltInCatalog.filebrowser
        let steps = units[0].install?.steps ?? []

        #expect(steps.count == 6)
        #expect(steps[0].action == .mkdir)
        #expect(steps[1].action == .mkdir)
        #expect(steps[2].action == .mkdir)
        #expect(steps[3].action == .symlink)
        #expect(steps[3].path == "${content_dir}/Files")
        #expect(steps[3].source == "${root_path}")
        #expect(steps[4].action == .exec)
        #expect(steps[4].path == "${executable_path}")
        #expect(steps[4].arguments?.contains("config") == true)
        #expect(steps[4].arguments?.contains("init") == true)
        #expect(steps[4].arguments?.contains("--disableExec") == true)
        #expect(steps[5].action == .exec)
        #expect(steps[5].arguments?.contains("users") == true)
        #expect(steps[5].arguments?.contains("add") == true)
        #expect(steps[5].arguments?.contains("${files_username}") == true)
        #expect(steps[5].arguments?.contains("${files_password}") == true)
        #expect(steps[5].arguments?.contains("--perm.admin") == true)
    }

    @Test("Runtime uses GitHub release artifact")
    func artifact() {
        let (_, _, units) = BuiltInCatalog.filebrowser
        let artifact = units[0].artifact

        #expect(artifact?.type == .githubRelease)
        #expect(artifact?.repo == "filebrowser/filebrowser")
        #expect(artifact?.version == "v2.63.2")
        #expect(artifact?.archive?.format == "tar.gz")
    }

    @Test("Planner keeps credentials out of launch arguments")
    func plannerKeepsCredentialsOutOfLaunchArguments() throws {
        let registry = BuiltInCatalog.makeRegistry()

        let plan = try Planner.planInstall(
            capabilityID: "haven.capability.filebrowser",
            registry: registry,
            settings: [
                "root_path": "/Volumes/Files",
                "files_username": "haven",
                "files_password": "secret-pass",
            ],
            baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
        )

        let planned = plan.service.units[0]
        let serviceRoot = "/tmp/haven-test/Services/haven.capability.filebrowser"

        #expect(planned.resolvedDirectories["data"] == "\(serviceRoot)/data")
        #expect(planned.resolvedDirectories["content"] == "\(serviceRoot)/data/served-roots")
        #expect(plan.service.resolvedSettings["files_username"] == nil)
        #expect(plan.service.resolvedSettings["files_password"] == nil)
        #expect(planned.resolvedLaunchArguments.contains("0.0.0.0"))
        #expect(planned.resolvedLaunchArguments.contains("\(serviceRoot)/data/served-roots"))
        #expect(planned.resolvedLaunchArguments.contains("\(serviceRoot)/data/filebrowser.db"))
        #expect(!planned.resolvedLaunchArguments.contains("haven"))
        #expect(!planned.resolvedLaunchArguments.contains("secret-pass"))
        #expect(!planned.resolvedLaunchArguments.contains("--noauth"))

        let install = try #require(planned.resolvedInstall)
        #expect(install.steps[2].path == "/Volumes/Files")
        #expect(install.steps[3].source == "/Volumes/Files")
        #expect(install.steps[4].arguments?.contains("\(serviceRoot)/data/filebrowser.db") == true)
        #expect(install.steps[4].arguments?.contains("\(serviceRoot)/data/served-roots") == true)
        #expect(install.steps[5].arguments?.contains("haven") == true)
        #expect(install.steps[5].arguments?.contains("secret-pass") == true)
    }

    @Test("Planner requires managed password")
    func plannerRequiresManagedPassword() throws {
        let registry = BuiltInCatalog.makeRegistry()

        #expect(throws: (any Error).self) {
            try Planner.planInstall(
                capabilityID: "haven.capability.filebrowser",
                registry: registry,
                settings: ["root_path": "/Volumes/Files"],
                baseDirectory: URL(fileURLWithPath: "/tmp/haven-test")
            )
        }
    }
}
