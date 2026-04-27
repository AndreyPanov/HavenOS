import Testing
import Foundation
import Synchronization
@testable import HavenBackup
@testable import HavenCore

@Suite("BackupEngine")
struct BackupEngineTests {

    private let engine = BackupEngine()

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

    private func populateServiceDirs(layout: ServiceDirectoryLayout) throws {
        let fm = FileManager.default
        for dir in layout.allDirectories {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
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

    // MARK: - Backup

    @Test("backupCapability creates Books/ root with config/manifest.json")
    func backupCreatesManifest() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        let scope = BackupScope().scope(for: state)
        let entry = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            serviceState: state,
            displayName: "Books"
        )

        #expect(entry.capabilityID == "haven.capability.kavita")
        #expect(entry.displayName == "Books")
        #expect(entry.status == .complete)

        // Manifest inside Books/config/
        let manifestFile = backupDir.appendingPathComponent("Books/config/manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifestFile.path))

        let manifest = try engine.readManifest(from: backupDir)
        #expect(manifest.version == 1)
        #expect(manifest.capabilities.count == 1)
        #expect(manifest.includesState)
    }

    @Test("backupCapability copies service dirs into config/service_*, skips logs")
    func backupCopiesCorrectDirs() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        let scope = BackupScope().scope(for: state)
        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            serviceState: state,
            displayName: "Books"
        )

        let fm = FileManager.default
        let root = backupDir.appendingPathComponent("Books")

        // Service data in config/service_data/
        let dbFile = root.appendingPathComponent("config/service_data/library.db")
        #expect(fm.fileExists(atPath: dbFile.path))
        #expect(try String(contentsOf: dbFile, encoding: .utf8) == "database content")

        // Service config in config/service_config/
        let configFile = root.appendingPathComponent("config/service_config/appsettings.json")
        #expect(fm.fileExists(atPath: configFile.path))
        #expect(try String(contentsOf: configFile, encoding: .utf8) == "config content")

        // Logs NOT copied
        let logDir = root.appendingPathComponent("logs")
        #expect(!fm.fileExists(atPath: logDir.path))
    }

    @Test("backupCapability saves state.json in config/")
    func backupExportsState() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        let scope = BackupScope().scope(for: state)
        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            serviceState: state,
            displayName: "Books"
        )

        let stateFile = backupDir.appendingPathComponent("Books/config/state.json")
        #expect(FileManager.default.fileExists(atPath: stateFile.path))
        let content = try String(contentsOf: stateFile, encoding: .utf8)
        #expect(content.contains("haven.capability.kavita"))
    }

    @Test("Content files are copied flat into data/, not nested")
    func contentCopiedFlat() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        let contentDir = try makeTempDir("Books")
        defer { cleanup(havenDir); cleanup(backupDir); cleanup(contentDir) }

        // Create some book files in the content directory
        try "epub data".write(
            to: contentDir.appendingPathComponent("novel.epub"),
            atomically: true, encoding: .utf8
        )
        try "pdf data".write(
            to: contentDir.appendingPathComponent("textbook.pdf"),
            atomically: true, encoding: .utf8
        )

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(
            servicesDir: paths.servicesDirectory,
            resolvedSettings: ["library_path": contentDir.path]
        )
        try populateServiceDirs(layout: state.directoryLayout)

        let scope = BackupScope().scope(for: state)
        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            serviceState: state,
            displayName: "Books"
        )

        let fm = FileManager.default
        let dataRoot = backupDir.appendingPathComponent("Books/data")

        // Files are directly in data/, not in data/Books/
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("novel.epub").path))
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("textbook.pdf").path))

        // No nested subfolder
        #expect(!fm.fileExists(atPath: dataRoot.appendingPathComponent(contentDir.lastPathComponent).path))
    }

    // MARK: - Credentials

    @Test("Credential export and restore round-trip")
    func credentialRoundTrip() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        let suiteName = "BackupEngineCredTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("test-token-123", forKey: "haven.kavita.token.haven.capability.kavita")
        defaults.set("admin", forKey: "haven.kavita.username.haven.capability.kavita")

        let keys = [
            "haven.kavita.token.haven.capability.kavita",
            "haven.kavita.username.haven.capability.kavita",
        ]

        let scope = BackupScope().scope(for: state)
        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            serviceState: state,
            credentialKeys: keys,
            defaults: defaults,
            displayName: "Books"
        )

        // Credentials file inside Books/config/
        let credsFile = backupDir.appendingPathComponent("Books/config/credentials.json")
        #expect(FileManager.default.fileExists(atPath: credsFile.path))

        // Clear and restore
        defaults.removeObject(forKey: "haven.kavita.token.haven.capability.kavita")
        defaults.removeObject(forKey: "haven.kavita.username.haven.capability.kavita")
        #expect(defaults.string(forKey: "haven.kavita.token.haven.capability.kavita") == nil)

        _ = try engine.restoreCapability(
            from: backupDir,
            havenPaths: paths,
            defaults: defaults
        )

        #expect(defaults.string(forKey: "haven.kavita.token.haven.capability.kavita") == "test-token-123")
        #expect(defaults.string(forKey: "haven.kavita.username.haven.capability.kavita") == "admin")
    }

    // MARK: - Round-trip

    @Test("Full backup → restore round-trip preserves data")
    func fullRoundTrip() throws {
        let sourceHaven = try makeTempDir("source-haven")
        let backupDir = try makeTempDir("backup")
        let targetHaven = try makeTempDir("target-haven")
        defer { cleanup(sourceHaven); cleanup(backupDir); cleanup(targetHaven) }

        let sourcePaths = HavenPaths(base: sourceHaven)
        let targetPaths = HavenPaths(base: targetHaven)

        let state = makeServiceState(servicesDir: sourcePaths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        let scope = BackupScope().scope(for: state)
        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            serviceState: state,
            displayName: "Books"
        )

        let manifest = try engine.restoreCapability(
            from: backupDir,
            havenPaths: targetPaths
        )

        #expect(manifest.capabilities.count == 1)

        let targetLayout = targetPaths.serviceLayout(for: "haven.capability.kavita")
        let dbFile = targetLayout.data.appendingPathComponent("library.db")
        #expect(FileManager.default.fileExists(atPath: dbFile.path))
        #expect(try String(contentsOf: dbFile, encoding: .utf8) == "database content")

        let configFile = targetLayout.config.appendingPathComponent("appsettings.json")
        #expect(FileManager.default.fileExists(atPath: configFile.path))
        #expect(try String(contentsOf: configFile, encoding: .utf8) == "config content")
    }

    // MARK: - Multi-capability

    @Test("backupAll backs up multiple capabilities to separate destinations")
    func backupAllMultipleCapabilities() throws {
        let havenDir = try makeTempDir("haven")
        let backupBooks = try makeTempDir("backup-books")
        let backupMusic = try makeTempDir("backup-music")
        defer { cleanup(havenDir); cleanup(backupBooks); cleanup(backupMusic) }

        let paths = HavenPaths(base: havenDir)
        let state1 = makeServiceState(
            capability: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            servicesDir: paths.servicesDirectory
        )
        let state2 = makeServiceState(
            capability: "haven.capability.navidrome",
            bundleID: "haven.bundle.navidrome",
            servicesDir: paths.servicesDirectory
        )
        try populateServiceDirs(layout: state1.directoryLayout)
        try populateServiceDirs(layout: state2.directoryLayout)

        let scopeBuilder = BackupScope()
        let scopes = [scopeBuilder.scope(for: state1), scopeBuilder.scope(for: state2)]
        let destinations: [String: URL] = [
            "haven.capability.kavita": backupBooks,
            "haven.capability.navidrome": backupMusic,
        ]

        let entries = try engine.backupAll(
            scopes: scopes,
            destinations: destinations,
            serviceStates: [
                "haven.capability.kavita": state1,
                "haven.capability.navidrome": state2,
            ],
            displayNames: [
                "haven.capability.kavita": "Books",
                "haven.capability.navidrome": "Music",
            ]
        )

        #expect(entries.count == 2)

        let fm = FileManager.default
        // Each has its own named root with manifest
        #expect(fm.fileExists(atPath: backupBooks.appendingPathComponent("Books/config/manifest.json").path))
        #expect(fm.fileExists(atPath: backupMusic.appendingPathComponent("Music/config/manifest.json").path))

        // Each has service data
        #expect(fm.fileExists(atPath: backupBooks.appendingPathComponent("Books/config/service_data/library.db").path))
        #expect(fm.fileExists(atPath: backupMusic.appendingPathComponent("Music/config/service_data/library.db").path))
    }

    // MARK: - Read manifest

    @Test("readManifest returns manifest without restoring")
    func readManifest() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        let scope = BackupScope().scope(for: state)
        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            serviceState: state,
            displayName: "Books"
        )

        let manifest = try engine.readManifest(from: backupDir)
        #expect(manifest.version == 1)
        #expect(manifest.capabilities.count == 1)
    }

    @Test("readManifest throws for missing manifest")
    func readManifestMissing() throws {
        let emptyDir = try makeTempDir("empty")
        defer { cleanup(emptyDir) }

        #expect(throws: BackupError.self) {
            try engine.readManifest(from: emptyDir)
        }
    }

    @Test("restoreCapability throws for missing manifest")
    func restoreMissingManifest() throws {
        let emptyDir = try makeTempDir("empty")
        let havenDir = try makeTempDir("haven")
        defer { cleanup(emptyDir); cleanup(havenDir) }

        #expect(throws: BackupError.self) {
            try engine.restoreCapability(
                from: emptyDir,
                havenPaths: HavenPaths(base: havenDir)
            )
        }
    }

    // MARK: - Credential discovery

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

    // MARK: - Overwrite

    @Test("Multiple backups overwrite previous backup cleanly")
    func overwriteBackup() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        let scope = BackupScope().scope(for: state)

        _ = try engine.backupCapability(
            scope: scope, destination: backupDir, serviceState: state, displayName: "Books"
        )

        // Modify data
        try "updated content".write(
            to: state.directoryLayout.data.appendingPathComponent("library.db"),
            atomically: true, encoding: .utf8
        )

        // Second backup overwrites
        _ = try engine.backupCapability(
            scope: scope, destination: backupDir, serviceState: state, displayName: "Books"
        )

        let dbFile = backupDir.appendingPathComponent("Books/config/service_data/library.db")
        #expect(try String(contentsOf: dbFile, encoding: .utf8) == "updated content")
    }

    // MARK: - Progress

    @Test("Progress callback is called during backup")
    func progressCallbacks() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        let messages = Mutex<[String]>([])
        let scope = BackupScope().scope(for: state)

        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            serviceState: state,
            displayName: "Books",
            progress: { msg in messages.withLock { $0.append(msg) } }
        )

        let captured = messages.withLock { $0 }
        #expect(captured.contains("Backing up Books…"))
        #expect(captured.contains("Backup of Books complete."))
    }

    // MARK: - Layout

    @Test("Backup creates Name/config + Name/data layout")
    func twoFolderLayout() throws {
        let havenDir = try makeTempDir("haven")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(havenDir); cleanup(backupDir) }

        let paths = HavenPaths(base: havenDir)
        let state = makeServiceState(servicesDir: paths.servicesDirectory)
        try populateServiceDirs(layout: state.directoryLayout)

        let scope = BackupScope().scope(for: state)
        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            serviceState: state,
            displayName: "Books"
        )

        let fm = FileManager.default

        // Root level has only the capability folder
        let rootContents = try fm.contentsOfDirectory(atPath: backupDir.path)
        #expect(rootContents == ["Books"])

        // Inside Books: only config/ and data/
        let booksContents = try fm.contentsOfDirectory(
            atPath: backupDir.appendingPathComponent("Books").path
        ).sorted()
        #expect(booksContents == ["config", "data"])

        // config/ contains service dirs + metadata
        let configContents = try fm.contentsOfDirectory(
            atPath: backupDir.appendingPathComponent("Books/config").path
        ).sorted()
        #expect(configContents.contains("manifest.json"))
        #expect(configContents.contains("state.json"))
        #expect(configContents.contains("service_config"))
        #expect(configContents.contains("service_data"))
    }
}
