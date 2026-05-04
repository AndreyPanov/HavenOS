import Testing
import Foundation
import HavenCore
@testable import HavenAppKit

@Suite("File Browser Files Facade")
struct FileBrowserFilesFacadeTests {

    @Test("Loads multiple roots from content_paths and mirrors served links")
    @MainActor func loadsMultipleRoots() throws {
        let rootA = try makeDirectory(named: "RootA")
        let rootB = try makeDirectory(named: "RootB")
        let capabilityID = "haven.capability.filebrowser.\(UUID().uuidString)"
        let (manager, layout, cleanup) = try makeServiceManager(
            capabilityID: capabilityID,
            resolvedSettings: [
                "root_path": rootA.path,
                "content_paths": "\(rootA.path);\(rootB.path)",
            ]
        )
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        manager.refresh()
        let facade = FileBrowserFilesFacade(
            capabilityID: capabilityID,
            serviceManager: manager
        )

        #expect(facade.roots.map(\.path) == [rootA.path, rootB.path])
        #expect(facade.roots.map(\.label) == ["RootA", "RootB"])
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: layout.data.appendingPathComponent("served-roots/RootA").path
            ) == rootA.path
        )
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: layout.data.appendingPathComponent("served-roots/RootB").path
            ) == rootB.path
        )
    }

    @Test("Adding and removing roots persists content_paths")
    @MainActor func addAndRemoveRoots() async throws {
        let rootA = try makeDirectory(named: "RootA")
        let rootB = try makeDirectory(named: "RootB")
        let capabilityID = "haven.capability.filebrowser.\(UUID().uuidString)"
        let (manager, layout, cleanup) = try makeServiceManager(
            capabilityID: capabilityID,
            resolvedSettings: ["root_path": rootA.path]
        )
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        manager.refresh()
        let facade = FileBrowserFilesFacade(
            capabilityID: capabilityID,
            serviceManager: manager
        )

        try await facade.addRoot(path: rootB.path)

        #expect(facade.roots.map(\.path) == [rootA.path, rootB.path])
        #expect(
            manager.storedState(for: capabilityID)?
                .resolvedSettings["root_path"] == rootA.path
        )
        #expect(
            manager.storedState(for: capabilityID)?
                .resolvedSettings["content_paths"] == "\(rootA.path);\(rootB.path)"
        )
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: layout.data.appendingPathComponent("served-roots/RootB").path
            ) == rootB.path
        )

        try await facade.removeRoot(facade.roots[0])

        #expect(facade.roots.map(\.path) == [rootB.path])
        #expect(
            manager.storedState(for: capabilityID)?
                .resolvedSettings["root_path"] == rootB.path
        )
        #expect(
            manager.storedState(for: capabilityID)?
                .resolvedSettings["content_paths"] == rootB.path
        )
    }

    @Test("Removing the last root is rejected")
    @MainActor func removingLastRootIsRejected() async throws {
        let root = try makeDirectory(named: "OnlyRoot")
        let capabilityID = "haven.capability.filebrowser.\(UUID().uuidString)"
        let (manager, _, cleanup) = try makeServiceManager(
            capabilityID: capabilityID,
            resolvedSettings: ["root_path": root.path]
        )
        defer {
            cleanup()
            try? FileManager.default.removeItem(at: root)
        }

        manager.refresh()
        let facade = FileBrowserFilesFacade(
            capabilityID: capabilityID,
            serviceManager: manager
        )

        do {
            try await facade.removeRoot(facade.roots[0])
            Issue.record("Expected removing the last root to throw")
        } catch {
            #expect(error.localizedDescription == "Files needs at least one folder.")
        }
    }

    private func makeDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-files-\(UUID().uuidString)")
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url.standardizedFileURL
    }

    @MainActor
    private func makeServiceManager(
        capabilityID: String,
        resolvedSettings: [String: String]
    ) throws -> (ServiceManager, ServiceDirectoryLayout, () -> Void) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-files-state-\(UUID().uuidString)")
        let stateDir = tmpDir.appendingPathComponent("State")
        let servicesDir = tmpDir.appendingPathComponent("Services")
        try FileManager.default.createDirectory(
            at: stateDir,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: servicesDir,
            withIntermediateDirectories: true
        )

        let layout = ServiceDirectoryLayout(
            servicesDirectory: servicesDir,
            capabilityID: capabilityID
        )
        let storedService = StoredServiceState(
            capability: capabilityID,
            bundleID: "haven.bundle.filebrowser-basic",
            installedAt: Date(),
            updatedAt: Date(),
            status: .running,
            resolvedSettings: resolvedSettings,
            portAssignments: [
                StoredPortAssignment(unitID: "haven.unit.filebrowser", port: 8080)
            ],
            runtimeUnits: ["haven.unit.filebrowser"],
            directoryLayout: layout
        )
        let state = HavenState(services: [capabilityID: storedService])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state)
            .write(to: stateDir.appendingPathComponent("services.json"))

        let manager = ServiceManager(basePath: tmpDir)
        return (manager, layout, {
            try? FileManager.default.removeItem(at: tmpDir)
        })
    }
}
