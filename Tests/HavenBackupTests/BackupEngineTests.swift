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

    // MARK: - Backup

    @Test("backupCapability creates Books/ root with config/manifest.json")
    func backupCreatesManifest() throws {
        let contentDir = try makeTempDir("Books")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(contentDir); cleanup(backupDir) }

        try "epub data".write(
            to: contentDir.appendingPathComponent("novel.epub"),
            atomically: true, encoding: .utf8
        )

        let scope = CapabilityBackupScope(
            capabilityID: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            contentPaths: [contentDir]
        )

        let entry = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            displayName: "Books"
        )

        #expect(entry.capabilityID == "haven.capability.kavita")
        #expect(entry.displayName == "Books")
        #expect(entry.status == .complete)

        // Manifest inside Books/
        let manifestFile = backupDir.appendingPathComponent("Books/manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifestFile.path))

        let manifest = try engine.readManifest(from: backupDir)
        #expect(manifest.version == 1)
        #expect(manifest.capabilities.count == 1)
    }

    @Test("Content files are copied flat into data/, not nested")
    func contentCopiedFlat() throws {
        let contentDir = try makeTempDir("Books")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(contentDir); cleanup(backupDir) }

        try "epub data".write(
            to: contentDir.appendingPathComponent("novel.epub"),
            atomically: true, encoding: .utf8
        )
        try "pdf data".write(
            to: contentDir.appendingPathComponent("textbook.pdf"),
            atomically: true, encoding: .utf8
        )

        let scope = CapabilityBackupScope(
            capabilityID: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            contentPaths: [contentDir]
        )

        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            displayName: "Books"
        )

        let fm = FileManager.default
        let dataRoot = backupDir.appendingPathComponent("Books/data")

        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("novel.epub").path))
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("textbook.pdf").path))
    }

    @Test("Backup layout: Name/manifest.json + Name/data only")
    func backupLayout() throws {
        let contentDir = try makeTempDir("Books")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(contentDir); cleanup(backupDir) }

        try "test".write(
            to: contentDir.appendingPathComponent("book.epub"),
            atomically: true, encoding: .utf8
        )

        let scope = CapabilityBackupScope(
            capabilityID: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            contentPaths: [contentDir]
        )

        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            displayName: "Books"
        )

        let fm = FileManager.default
        let rootContents = try fm.contentsOfDirectory(atPath: backupDir.path)
        #expect(rootContents == ["Books"])

        let booksContents = try fm.contentsOfDirectory(
            atPath: backupDir.appendingPathComponent("Books").path
        ).sorted()
        #expect(booksContents == ["data", "manifest.json"])
    }

    @Test("Empty content paths results in failed status")
    func emptyContentPaths() throws {
        let backupDir = try makeTempDir("backup")
        defer { cleanup(backupDir) }

        let scope = CapabilityBackupScope(
            capabilityID: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            contentPaths: []
        )

        let entry = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            displayName: "Books"
        )

        #expect(entry.status == .failed)
    }

    // MARK: - Restore

    @Test("restoreFiles copies backup data/ to library folder")
    func restoreFilesToLibrary() throws {
        let contentDir = try makeTempDir("Books")
        let backupDir = try makeTempDir("backup")
        let restoreDir = try makeTempDir("restored")
        defer { cleanup(contentDir); cleanup(backupDir); cleanup(restoreDir) }

        try "epub data".write(
            to: contentDir.appendingPathComponent("novel.epub"),
            atomically: true, encoding: .utf8
        )

        let scope = CapabilityBackupScope(
            capabilityID: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            contentPaths: [contentDir]
        )

        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            displayName: "Books"
        )

        try engine.restoreFiles(from: backupDir, to: restoreDir, displayName: "Books")

        let fm = FileManager.default
        let restoredFile = restoreDir.appendingPathComponent("novel.epub")
        #expect(fm.fileExists(atPath: restoredFile.path))
        #expect(try String(contentsOf: restoredFile, encoding: .utf8) == "epub data")
    }

    @Test("restoreFiles throws for missing manifest")
    func restoreMissingManifest() throws {
        let emptyDir = try makeTempDir("empty")
        let targetDir = try makeTempDir("target")
        defer { cleanup(emptyDir); cleanup(targetDir) }

        #expect(throws: BackupError.self) {
            try engine.restoreFiles(from: emptyDir, to: targetDir)
        }
    }

    // MARK: - Multi-capability

    @Test("backupAll backs up multiple capabilities to separate destinations")
    func backupAllMultipleCapabilities() throws {
        let booksContent = try makeTempDir("books-content")
        let musicContent = try makeTempDir("music-content")
        let backupBooks = try makeTempDir("backup-books")
        let backupMusic = try makeTempDir("backup-music")
        defer {
            cleanup(booksContent); cleanup(musicContent)
            cleanup(backupBooks); cleanup(backupMusic)
        }

        try "book.epub".write(
            to: booksContent.appendingPathComponent("book.epub"),
            atomically: true, encoding: .utf8
        )
        try "song.mp3".write(
            to: musicContent.appendingPathComponent("song.mp3"),
            atomically: true, encoding: .utf8
        )

        let scopes = [
            CapabilityBackupScope(
                capabilityID: "haven.capability.kavita",
                bundleID: "haven.bundle.kavita",
                contentPaths: [booksContent]
            ),
            CapabilityBackupScope(
                capabilityID: "haven.capability.navidrome",
                bundleID: "haven.bundle.navidrome",
                contentPaths: [musicContent]
            ),
        ]
        let destinations: [String: URL] = [
            "haven.capability.kavita": backupBooks,
            "haven.capability.navidrome": backupMusic,
        ]

        let entries = try engine.backupAll(
            scopes: scopes,
            destinations: destinations,
            displayNames: [
                "haven.capability.kavita": "Books",
                "haven.capability.navidrome": "Music",
            ]
        )

        #expect(entries.count == 2)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: backupBooks.appendingPathComponent("Books/manifest.json").path))
        #expect(fm.fileExists(atPath: backupMusic.appendingPathComponent("Music/manifest.json").path))
        #expect(fm.fileExists(atPath: backupBooks.appendingPathComponent("Books/data/book.epub").path))
        #expect(fm.fileExists(atPath: backupMusic.appendingPathComponent("Music/data/song.mp3").path))
    }

    // MARK: - Read manifest

    @Test("readManifest returns manifest without restoring")
    func readManifest() throws {
        let contentDir = try makeTempDir("Books")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(contentDir); cleanup(backupDir) }

        try "test".write(
            to: contentDir.appendingPathComponent("book.epub"),
            atomically: true, encoding: .utf8
        )

        let scope = CapabilityBackupScope(
            capabilityID: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            contentPaths: [contentDir]
        )

        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
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

    // MARK: - Overwrite / Incremental

    @Test("Multiple backups overwrite previous backup cleanly")
    func overwriteBackup() throws {
        let contentDir = try makeTempDir("Books")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(contentDir); cleanup(backupDir) }

        let bookFile = contentDir.appendingPathComponent("book.epub")
        try "original".write(to: bookFile, atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            contentPaths: [contentDir]
        )

        _ = try engine.backupCapability(
            scope: scope, destination: backupDir, displayName: "Books"
        )

        // Modify content
        try "updated".write(to: bookFile, atomically: true, encoding: .utf8)

        // Second backup overwrites
        _ = try engine.backupCapability(
            scope: scope, destination: backupDir, displayName: "Books"
        )

        let backedUp = backupDir.appendingPathComponent("Books/data/book.epub")
        #expect(try String(contentsOf: backedUp, encoding: .utf8) == "updated")
    }

    // MARK: - Progress

    @Test("Progress callback is called during backup")
    func progressCallbacks() throws {
        let contentDir = try makeTempDir("Books")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(contentDir); cleanup(backupDir) }

        try "test".write(
            to: contentDir.appendingPathComponent("book.epub"),
            atomically: true, encoding: .utf8
        )

        let messages = Mutex<[String]>([])
        let scope = CapabilityBackupScope(
            capabilityID: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            contentPaths: [contentDir]
        )

        _ = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            displayName: "Books",
            progress: { msg in messages.withLock { $0.append(msg) } }
        )

        let captured = messages.withLock { $0 }
        #expect(captured.contains("Backing up Books…"))
        #expect(captured.contains("Backup of Books complete."))
    }
}
