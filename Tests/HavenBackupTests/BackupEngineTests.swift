import Testing
import Foundation
import Synchronization
@testable import HavenBackup
@testable import HavenCore

@Suite("BackupEngine")
struct BackupEngineTests {

    private let engine = BackupEngine()

    /// Create a temp directory and return its URL. Caller must clean up.
    private func makeTempDir(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HavenBackupTests")
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeServiceState(
        capability: String = "haven.capability.kavita",
        bundleID: String = "haven.bundle.kavita",
        servicesDir: URL,
        resolvedSettings: [String: String] = [:]
    ) -> StoredServiceState {
        let layout = ServiceDirectoryLayout(
            servicesDirectory: servicesDir,
            capabilityID: capability
        )
        return StoredServiceState(
            capability: capability,
            bundleID: bundleID,
            installedAt: Date(timeIntervalSince1970: 1700000000),
            updatedAt: Date(timeIntervalSince1970: 1700000000),
            status: .running,
            resolvedSettings: resolvedSettings,
            portAssignments: [],
            runtimeUnits: ["unit1"],
            directoryLayout: layout
        )
    }

    /// Set up a service directory with some test data files.
    private func populateServiceDirs(layout: ServiceDirectoryLayout) throws {
        let fm = FileManager.default
        for dir in layout.allDirectories {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Write test data
        try "database content".write(
            to: layout.data.appendingPathComponent("library.db"),
            atomically: true, encoding: .utf8
        )
        try "config content".write(
            to: layout.config.appendingPathComponent("appsettings.json"),
            atomically: true, encoding: .utf8
        )
        try "log content".write(
            to: layout.logs.appendingPathComponent("service.log"),
            atomically: true, encoding: .utf8
        )
    }

    @Test("Backup creates manifest at destination")
    func backupCreatesManifest() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        // Write a state file
        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        try "{}".write(to: paths.stateFile, atomically: true, encoding: .utf8)

        let scope = BackupScope().scope(for: state)
        let manifest = try engine.backup(
            scopes: [scope],
            destination: backupDir,
            stateFileURL: paths.stateFile,
            displayNames: [state.capability: "Books"]
        )

        #expect(manifest.version == 1)
        #expect(manifest.capabilities.count == 1)
        #expect(manifest.capabilities[0].capabilityID == "haven.capability.kavita")
        #expect(manifest.capabilities[0].displayName == "Books")
        #expect(manifest.capabilities[0].status == .complete)
        #expect(manifest.includesState)

        // Manifest file exists on disk
        let manifestFile = backupDir.appendingPathComponent("manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifestFile.path))
    }

    @Test("Backup copies data and config, skips logs")
    func backupCopiesCorrectDirs() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        try "{}".write(to: paths.stateFile, atomically: true, encoding: .utf8)

        let scope = BackupScope().scope(for: state)
        _ = try engine.backup(
            scopes: [scope],
            destination: backupDir,
            stateFileURL: paths.stateFile
        )

        let fm = FileManager.default
        let capDir = backupDir
            .appendingPathComponent("capabilities")
            .appendingPathComponent("haven.capability.kavita")

        // Data was copied
        let dbFile = capDir.appendingPathComponent("data/library.db")
        #expect(fm.fileExists(atPath: dbFile.path))
        #expect(try String(contentsOf: dbFile, encoding: .utf8) == "database content")

        // Config was copied
        let configFile = capDir.appendingPathComponent("config/appsettings.json")
        #expect(fm.fileExists(atPath: configFile.path))

        // Logs were NOT copied (not in scope)
        let logDir = capDir.appendingPathComponent("logs")
        #expect(!fm.fileExists(atPath: logDir.path))
    }

    @Test("Backup exports services.json")
    func backupExportsState() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        try "{\"services\":{}}".write(to: paths.stateFile, atomically: true, encoding: .utf8)

        _ = try engine.backup(
            scopes: [],
            destination: backupDir,
            stateFileURL: paths.stateFile
        )

        let restoredState = backupDir
            .appendingPathComponent("state")
            .appendingPathComponent("services.json")
        #expect(FileManager.default.fileExists(atPath: restoredState.path))
        let content = try String(contentsOf: restoredState, encoding: .utf8)
        #expect(content.contains("services"))
    }

    @Test("Backup exports and restores credentials")
    func credentialRoundTrip() throws {
        let backupDir = try makeTempDir("backup")
        let havenDir = try makeTempDir("haven")
        defer { cleanup(backupDir); cleanup(havenDir) }

        let paths = HavenPaths(base: havenDir)
        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        try "{}".write(to: paths.stateFile, atomically: true, encoding: .utf8)

        // Set up credentials in a test defaults suite
        let suiteName = "BackupEngineCredTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("test-token-123", forKey: "haven.kavita.token.haven.capability.kavita")
        defaults.set("admin", forKey: "haven.kavita.username.haven.capability.kavita")

        let keys = [
            "haven.kavita.token.haven.capability.kavita",
            "haven.kavita.username.haven.capability.kavita",
        ]

        // Backup
        _ = try engine.backup(
            scopes: [],
            destination: backupDir,
            stateFileURL: paths.stateFile,
            credentialKeys: keys,
            defaults: defaults
        )

        // Clear credentials
        defaults.removeObject(forKey: "haven.kavita.token.haven.capability.kavita")
        defaults.removeObject(forKey: "haven.kavita.username.haven.capability.kavita")
        #expect(defaults.string(forKey: "haven.kavita.token.haven.capability.kavita") == nil)

        // Restore
        _ = try engine.restore(
            from: backupDir,
            havenPaths: paths,
            defaults: defaults
        )

        // Credentials restored
        #expect(defaults.string(forKey: "haven.kavita.token.haven.capability.kavita") == "test-token-123")
        #expect(defaults.string(forKey: "haven.kavita.username.haven.capability.kavita") == "admin")
    }

    @Test("Full backup → restore round-trip preserves data")
    func fullRoundTrip() throws {
        let sourceHaven = try makeTempDir("source-haven")
        let backupDir = try makeTempDir("backup")
        let targetHaven = try makeTempDir("target-haven")
        defer { cleanup(sourceHaven); cleanup(backupDir); cleanup(targetHaven) }

        let sourcePaths = HavenPaths(base: sourceHaven)
        let targetPaths = HavenPaths(base: targetHaven)

        // Set up source service
        let state = makeServiceState(servicesDir: sourcePaths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        // Write state file
        try FileManager.default.createDirectory(at: sourcePaths.stateDirectory, withIntermediateDirectories: true)
        try "{\"services\":{\"haven.capability.kavita\":{}}}".write(
            to: sourcePaths.stateFile, atomically: true, encoding: .utf8
        )

        // Backup
        let scope = BackupScope().scope(for: state)
        _ = try engine.backup(
            scopes: [scope],
            destination: backupDir,
            stateFileURL: sourcePaths.stateFile,
            displayNames: [state.capability: "Books"]
        )

        // Restore to target
        let manifest = try engine.restore(
            from: backupDir,
            havenPaths: targetPaths
        )

        #expect(manifest.capabilities.count == 1)

        // Verify data was restored
        let targetLayout = targetPaths.serviceLayout(for: "haven.capability.kavita")
        let dbFile = targetLayout.data.appendingPathComponent("library.db")
        #expect(FileManager.default.fileExists(atPath: dbFile.path))
        #expect(try String(contentsOf: dbFile, encoding: .utf8) == "database content")

        let configFile = targetLayout.config.appendingPathComponent("appsettings.json")
        #expect(FileManager.default.fileExists(atPath: configFile.path))
        #expect(try String(contentsOf: configFile, encoding: .utf8) == "config content")

        // State file restored
        #expect(FileManager.default.fileExists(atPath: targetPaths.stateFile.path))
    }

    @Test("Restore with capability filter only restores selected")
    func restoreWithFilter() throws {
        let sourceHaven = try makeTempDir("source-haven")
        let backupDir = try makeTempDir("backup")
        let targetHaven = try makeTempDir("target-haven")
        defer { cleanup(sourceHaven); cleanup(backupDir); cleanup(targetHaven) }

        let sourcePaths = HavenPaths(base: sourceHaven)
        let targetPaths = HavenPaths(base: targetHaven)

        // Set up two services
        let state1 = makeServiceState(
            capability: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            servicesDir: sourcePaths.servicesDirectory
        )
        let state2 = makeServiceState(
            capability: "haven.capability.navidrome",
            bundleID: "haven.bundle.navidrome",
            servicesDir: sourcePaths.servicesDirectory
        )
        try populateServiceDirs(layout: state1.directoryLayout)
        try populateServiceDirs(layout: state2.directoryLayout)

        try FileManager.default.createDirectory(at: sourcePaths.stateDirectory, withIntermediateDirectories: true)
        try "{}".write(to: sourcePaths.stateFile, atomically: true, encoding: .utf8)

        let scope = BackupScope()
        let scopes = [scope.scope(for: state1), scope.scope(for: state2)]

        _ = try engine.backup(
            scopes: scopes,
            destination: backupDir,
            stateFileURL: sourcePaths.stateFile
        )

        // Only restore kavita
        _ = try engine.restore(
            from: backupDir,
            capabilityIDs: ["haven.capability.kavita"],
            havenPaths: targetPaths
        )

        let kavitaData = targetPaths.serviceLayout(for: "haven.capability.kavita").data
        let navidromeData = targetPaths.serviceLayout(for: "haven.capability.navidrome").data

        #expect(FileManager.default.fileExists(atPath: kavitaData.path))
        #expect(!FileManager.default.fileExists(atPath: navidromeData.path))
    }

    @Test("readManifest returns manifest without restoring")
    func readManifest() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        try "{}".write(to: paths.stateFile, atomically: true, encoding: .utf8)

        _ = try engine.backup(
            scopes: [],
            destination: backupDir,
            stateFileURL: paths.stateFile
        )

        let manifest = try engine.readManifest(from: backupDir)
        #expect(manifest.version == 1)
        #expect(manifest.capabilities.isEmpty)
    }

    @Test("readManifest throws for missing manifest")
    func readManifestMissing() throws {
        let emptyDir = try makeTempDir("empty")
        defer { cleanup(emptyDir) }

        #expect(throws: BackupError.self) {
            try engine.readManifest(from: emptyDir)
        }
    }

    @Test("Restore throws for missing manifest")
    func restoreMissingManifest() throws {
        let emptyDir = try makeTempDir("empty")
        let havenDir = try makeTempDir("haven")
        defer { cleanup(emptyDir); cleanup(havenDir) }

        #expect(throws: BackupError.self) {
            try engine.restore(
                from: emptyDir,
                havenPaths: HavenPaths(base: havenDir)
            )
        }
    }

    @Test("discoverCredentialKeys finds haven credential keys")
    func discoverKeys() {
        let suiteName = "BackupEngineDiscoverTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("val", forKey: "haven.kavita.token.cap1")
        defaults.set("val", forKey: "haven.navidrome.password.cap2")
        defaults.set("val", forKey: "haven.jellyfin.managedUser.cap3")
        defaults.set("val", forKey: "unrelated.key")

        let keys = BackupEngine.discoverCredentialKeys(from: defaults)
        #expect(keys.count == 3)
        #expect(keys.contains("haven.kavita.token.cap1"))
        #expect(keys.contains("haven.navidrome.password.cap2"))
        #expect(keys.contains("haven.jellyfin.managedUser.cap3"))
        #expect(!keys.contains("unrelated.key"))
    }

    @Test("Multiple backups overwrite previous backup cleanly")
    func overwriteBackup() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        try "{}".write(to: paths.stateFile, atomically: true, encoding: .utf8)

        let scope = BackupScope().scope(for: state)

        // First backup
        _ = try engine.backup(scopes: [scope], destination: backupDir, stateFileURL: paths.stateFile)

        // Modify data
        try "updated content".write(
            to: state.directoryLayout.data.appendingPathComponent("library.db"),
            atomically: true, encoding: .utf8
        )

        // Second backup overwrites
        _ = try engine.backup(scopes: [scope], destination: backupDir, stateFileURL: paths.stateFile)

        // Verify updated content
        let capDir = backupDir
            .appendingPathComponent("capabilities")
            .appendingPathComponent("haven.capability.kavita")
        let dbFile = capDir.appendingPathComponent("data/library.db")
        #expect(try String(contentsOf: dbFile, encoding: .utf8) == "updated content")
    }

    @Test("Progress callback is called during backup")
    func progressCallbacks() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        try FileManager.default.createDirectory(at: paths.stateDirectory, withIntermediateDirectories: true)
        try "{}".write(to: paths.stateFile, atomically: true, encoding: .utf8)

        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        let messages = Mutex<[String]>([])
        let scope = BackupScope().scope(for: state)

        _ = try engine.backup(
            scopes: [scope],
            destination: backupDir,
            stateFileURL: paths.stateFile,
            displayNames: [state.capability: "Books"],
            progress: { msg in messages.withLock { $0.append(msg) } }
        )

        let captured = messages.withLock { $0 }
        #expect(captured.contains("Backing up Books…"))
        #expect(captured.contains("Backup complete."))
    }
}
