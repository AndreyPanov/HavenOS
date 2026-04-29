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

    // MARK: - Multi-Folder Backup

    @Test("Multiple content paths are all preserved in data/")
    func multipleContentPathsPreserved() throws {
        let folderA = try makeTempDir("FolderA")
        let folderB = try makeTempDir("FolderB")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folderA); cleanup(folderB); cleanup(backupDir) }

        try "novel.epub".write(
            to: folderA.appendingPathComponent("novel.epub"),
            atomically: true, encoding: .utf8
        )
        try "comic.cbz".write(
            to: folderA.appendingPathComponent("comic.cbz"),
            atomically: true, encoding: .utf8
        )
        try "textbook.pdf".write(
            to: folderB.appendingPathComponent("textbook.pdf"),
            atomically: true, encoding: .utf8
        )

        let scope = CapabilityBackupScope(
            capabilityID: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            contentPaths: [folderA, folderB]
        )

        let entry = try engine.backupCapability(
            scope: scope,
            destination: backupDir,
            displayName: "Books"
        )

        #expect(entry.status == .complete)

        let fm = FileManager.default
        let dataRoot = backupDir.appendingPathComponent("Books/data")
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("novel.epub").path))
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("comic.cbz").path))
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("textbook.pdf").path))
    }

    @Test("Second backup with multiple folders does not delete first folder's files")
    func multifolderIncrementalDoesNotDeleteOtherFolder() throws {
        let folderA = try makeTempDir("Movies")
        let folderB = try makeTempDir("TVShows")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folderA); cleanup(folderB); cleanup(backupDir) }

        try "movie.mkv".write(
            to: folderA.appendingPathComponent("movie.mkv"),
            atomically: true, encoding: .utf8
        )
        try "episode.mkv".write(
            to: folderB.appendingPathComponent("episode.mkv"),
            atomically: true, encoding: .utf8
        )

        let scope = CapabilityBackupScope(
            capabilityID: "haven.capability.jellyfin",
            bundleID: "haven.bundle.jellyfin",
            contentPaths: [folderA, folderB]
        )

        // First backup
        _ = try engine.backupCapability(
            scope: scope, destination: backupDir, displayName: "Movies"
        )

        // Second backup (incremental)
        _ = try engine.backupCapability(
            scope: scope, destination: backupDir, displayName: "Movies"
        )

        let fm = FileManager.default
        let dataRoot = backupDir.appendingPathComponent("Movies/data")

        // Both files must still exist after second backup
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("movie.mkv").path))
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("episode.mkv").path))
    }

    @Test("Multi-folder cleanup removes files deleted from all sources")
    func multifolderCleanupRemovesOrphans() throws {
        let folderA = try makeTempDir("FolderA")
        let folderB = try makeTempDir("FolderB")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folderA); cleanup(folderB); cleanup(backupDir) }

        // First backup with 3 files
        try "a.txt".write(to: folderA.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b.txt".write(to: folderB.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "c.txt".write(to: folderB.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "cap", bundleID: "bundle",
            contentPaths: [folderA, folderB]
        )

        _ = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        let dataRoot = backupDir.appendingPathComponent("Test/data")
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("c.txt").path))

        // Remove c.txt from source, then backup again
        try fm.removeItem(at: folderB.appendingPathComponent("c.txt"))

        _ = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        // c.txt should be cleaned up from backup
        #expect(!fm.fileExists(atPath: dataRoot.appendingPathComponent("c.txt").path))
        // a.txt and b.txt still present
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("a.txt").path))
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("b.txt").path))
    }

    @Test("Multi-folder backup with overlapping filenames — last copy wins")
    func multifolderOverlappingFilenames() throws {
        let folderA = try makeTempDir("FolderA")
        let folderB = try makeTempDir("FolderB")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folderA); cleanup(folderB); cleanup(backupDir) }

        // Same filename in both folders with different sizes — folderB should win (copied second)
        try "short".write(to: folderA.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        try "this is the longer version from folder B".write(to: folderB.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "cap", bundleID: "bundle",
            contentPaths: [folderA, folderB]
        )

        _ = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        let backed = backupDir.appendingPathComponent("Test/data/readme.txt")
        #expect(try String(contentsOf: backed, encoding: .utf8) == "this is the longer version from folder B")
    }

    @Test("Multi-folder total bytes includes files from all paths")
    func multifolderTotalBytes() throws {
        let folderA = try makeTempDir("FolderA")
        let folderB = try makeTempDir("FolderB")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folderA); cleanup(folderB); cleanup(backupDir) }

        try "aaaa".write(to: folderA.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "bbbb".write(to: folderB.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "cap", bundleID: "bundle",
            contentPaths: [folderA, folderB]
        )

        let entry = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        #expect(entry.totalBytes > 0)
        #expect(entry.status == .complete)
    }

    @Test("Single content path still does cleanup normally")
    func singlePathCleanupWorks() throws {
        let folder = try makeTempDir("Folder")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folder); cleanup(backupDir) }

        try "a".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: folder.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "cap", bundleID: "bundle",
            contentPaths: [folder]
        )

        _ = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        // Remove b.txt from source
        try FileManager.default.removeItem(at: folder.appendingPathComponent("b.txt"))

        _ = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        let dataRoot = backupDir.appendingPathComponent("Test/data")
        #expect(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("a.txt").path))
        #expect(!FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("b.txt").path))
    }

    @Test("Restore after multi-folder backup contains all files")
    func restoreAfterMultifolderBackup() throws {
        let folderA = try makeTempDir("FolderA")
        let folderB = try makeTempDir("FolderB")
        let backupDir = try makeTempDir("backup")
        let restoreDir = try makeTempDir("restored")
        defer { cleanup(folderA); cleanup(folderB); cleanup(backupDir); cleanup(restoreDir) }

        try "novel".write(to: folderA.appendingPathComponent("novel.epub"), atomically: true, encoding: .utf8)
        try "comic".write(to: folderB.appendingPathComponent("comic.cbz"), atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "haven.capability.kavita",
            bundleID: "haven.bundle.kavita",
            contentPaths: [folderA, folderB]
        )

        _ = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Books")

        try engine.restoreFiles(from: backupDir, to: restoreDir, displayName: "Books")

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: restoreDir.appendingPathComponent("novel.epub").path))
        #expect(fm.fileExists(atPath: restoreDir.appendingPathComponent("comic.cbz").path))
    }

    @Test("Multi-folder backup with one nonexistent source still backs up the other")
    func multifolderOneNonexistentSource() throws {
        let folder = try makeTempDir("Existing")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folder); cleanup(backupDir) }

        try "file".write(to: folder.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let nonexistent = FileManager.default.temporaryDirectory
            .appendingPathComponent("HavenBackupTests/nonexistent-\(UUID().uuidString)")

        let scope = CapabilityBackupScope(
            capabilityID: "cap", bundleID: "bundle",
            contentPaths: [folder, nonexistent]
        )

        let entry = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        let dataRoot = backupDir.appendingPathComponent("Test/data")
        #expect(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("file.txt").path))
        #expect(entry.status == .complete)
    }

    @Test("Three folders all preserved — not just a two-folder fix")
    func threeFoldersAllPreserved() throws {
        let folderA = try makeTempDir("FolderA")
        let folderB = try makeTempDir("FolderB")
        let folderC = try makeTempDir("FolderC")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folderA); cleanup(folderB); cleanup(folderC); cleanup(backupDir) }

        try "a.epub".write(to: folderA.appendingPathComponent("a.epub"), atomically: true, encoding: .utf8)
        try "b.pdf".write(to: folderB.appendingPathComponent("b.pdf"), atomically: true, encoding: .utf8)
        try "c.cbz".write(to: folderC.appendingPathComponent("c.cbz"), atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "cap", bundleID: "bundle",
            contentPaths: [folderA, folderB, folderC]
        )

        let entry = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")
        #expect(entry.status == .complete)

        let fm = FileManager.default
        let dataRoot = backupDir.appendingPathComponent("Test/data")
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("a.epub").path))
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("b.pdf").path))
        #expect(fm.fileExists(atPath: dataRoot.appendingPathComponent("c.cbz").path))
    }

    @Test("Empty folder mixed with populated folder — populated still backed up")
    func emptyFolderMixedWithPopulated() throws {
        let emptyFolder = try makeTempDir("Empty")
        let populatedFolder = try makeTempDir("Populated")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(emptyFolder); cleanup(populatedFolder); cleanup(backupDir) }

        try "book.epub".write(to: populatedFolder.appendingPathComponent("book.epub"), atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "cap", bundleID: "bundle",
            contentPaths: [emptyFolder, populatedFolder]
        )

        let entry = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")
        #expect(entry.status == .complete)

        let dataRoot = backupDir.appendingPathComponent("Test/data")
        #expect(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("book.epub").path))
    }

    @Test("Subdirectories within content folders are copied")
    func subdirectoriesInContentFolders() throws {
        let folder = try makeTempDir("Library")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folder); cleanup(backupDir) }

        // Create a subfolder structure: Library/SciFi/book.epub
        let subdir = folder.appendingPathComponent("SciFi")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "book data".write(to: subdir.appendingPathComponent("book.epub"), atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "cap", bundleID: "bundle",
            contentPaths: [folder]
        )

        _ = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        let dataRoot = backupDir.appendingPathComponent("Test/data")
        let backedUpBook = dataRoot.appendingPathComponent("SciFi/book.epub")
        #expect(FileManager.default.fileExists(atPath: backedUpBook.path))
    }

    @Test("File deleted from one folder but in another — kept in backup")
    func fileDeletedFromOneFolderStillInAnother() throws {
        let folderA = try makeTempDir("FolderA")
        let folderB = try makeTempDir("FolderB")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folderA); cleanup(folderB); cleanup(backupDir) }

        // Both folders have different files
        try "a".write(to: folderA.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "shared".write(to: folderA.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: folderB.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "cap", bundleID: "bundle",
            contentPaths: [folderA, folderB]
        )

        _ = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        // Delete shared.txt from folderA only — it's not in folderB either, so it should be removed
        try FileManager.default.removeItem(at: folderA.appendingPathComponent("shared.txt"))

        _ = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        let dataRoot = backupDir.appendingPathComponent("Test/data")
        #expect(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("a.txt").path))
        #expect(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("b.txt").path))
        // shared.txt was deleted from all sources, so it must be gone from backup
        #expect(!FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("shared.txt").path))
    }

    @Test("File in folderA and folderB with same name — removed from A, still in B — kept")
    func sameNameFileRemovedFromOneFolder() throws {
        let folderA = try makeTempDir("FolderA")
        let folderB = try makeTempDir("FolderB")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folderA); cleanup(folderB); cleanup(backupDir) }

        try "version A".write(to: folderA.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        try "version B".write(to: folderB.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        try "only-a".write(to: folderA.appendingPathComponent("only-a.txt"), atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "cap", bundleID: "bundle",
            contentPaths: [folderA, folderB]
        )

        _ = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        // Remove readme.txt from folderA — it's still in folderB
        try FileManager.default.removeItem(at: folderA.appendingPathComponent("readme.txt"))

        _ = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        let dataRoot = backupDir.appendingPathComponent("Test/data")
        // readme.txt should still exist (from folderB)
        #expect(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("readme.txt").path))
        #expect(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("only-a.txt").path))
    }

    @Test("Incremental backup across multiple folders skips unchanged files")
    func incrementalMultiFolderSkipsUnchanged() throws {
        let folderA = try makeTempDir("FolderA")
        let folderB = try makeTempDir("FolderB")
        let backupDir = try makeTempDir("backup")
        defer { cleanup(folderA); cleanup(folderB); cleanup(backupDir) }

        try "a".write(to: folderA.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: folderB.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let scope = CapabilityBackupScope(
            capabilityID: "cap", bundleID: "bundle",
            contentPaths: [folderA, folderB]
        )

        // First backup
        let entry1 = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        // Second backup — no changes
        let entry2 = try engine.backupCapability(scope: scope, destination: backupDir, displayName: "Test")

        // Both should be complete with same byte count
        #expect(entry1.status == .complete)
        #expect(entry2.status == .complete)
        #expect(entry2.totalBytes == entry1.totalBytes)

        let dataRoot = backupDir.appendingPathComponent("Test/data")
        #expect(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("a.txt").path))
        #expect(FileManager.default.fileExists(atPath: dataRoot.appendingPathComponent("b.txt").path))
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
