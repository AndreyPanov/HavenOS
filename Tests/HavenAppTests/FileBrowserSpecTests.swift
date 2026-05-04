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
        #expect(password?.defaultValue == nil)
        #expect(password?.required == true)
    }

    @Test("Runtime uses authentication, not noauth")
    func runtimeUsesAuthentication() {
        let (_, _, units) = BuiltInCatalog.filebrowser
        let args = units[0].launchArguments

        #expect(!args.contains("--noauth"))
        #expect(args.contains("--username"))
        #expect(args.contains("${files_username}"))
        #expect(args.contains("--password"))
        #expect(args.contains("${files_password}"))
        #expect(args.contains("--disableExec"))
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

    @Test("Planner expands secure launch arguments")
    func plannerExpandsSecureLaunchArguments() throws {
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
        #expect(planned.resolvedDirectories["content"] == "/Volumes/Files")
        #expect(planned.resolvedLaunchArguments.contains("0.0.0.0"))
        #expect(planned.resolvedLaunchArguments.contains("/Volumes/Files"))
        #expect(planned.resolvedLaunchArguments.contains("\(serviceRoot)/data/filebrowser.db"))
        #expect(planned.resolvedLaunchArguments.contains("haven"))
        #expect(planned.resolvedLaunchArguments.contains("secret-pass"))
        #expect(!planned.resolvedLaunchArguments.contains("--noauth"))
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
