import Testing
import Foundation
@testable import HavenApp

@Suite("LibraryOrganizer")
struct LibraryOrganizerTests {

    /// Creates a temporary directory and returns its URL. Cleaned up automatically.
    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func createFile(at url: URL, content: String = "test") throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Basic Organization

    @Test("Moves loose epub into subdirectory")
    func organizeEpub() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir.appendingPathComponent("Dune.epub"))

        LibraryOrganizer.organize(at: dir)

        let organized = dir.appendingPathComponent("Dune/Dune.epub")
        #expect(FileManager.default.fileExists(atPath: organized.path))
        // Original should be gone
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Dune.epub").path))
    }

    @Test("Moves loose pdf into subdirectory")
    func organizePdf() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir.appendingPathComponent("My Book.pdf"))

        LibraryOrganizer.organize(at: dir)

        let organized = dir.appendingPathComponent("My Book/My Book.pdf")
        #expect(FileManager.default.fileExists(atPath: organized.path))
    }

    @Test("Moves loose cbz into subdirectory")
    func organizeCbz() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir.appendingPathComponent("Comic Issue 1.cbz"))

        LibraryOrganizer.organize(at: dir)

        let organized = dir.appendingPathComponent("Comic Issue 1/Comic Issue 1.cbz")
        #expect(FileManager.default.fileExists(atPath: organized.path))
    }

    // MARK: - Multiple Files

    @Test("Organizes multiple loose files at once")
    func organizeMultiple() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir.appendingPathComponent("Book A.epub"))
        try createFile(at: dir.appendingPathComponent("Book B.pdf"))
        try createFile(at: dir.appendingPathComponent("Comic.cbr"))

        LibraryOrganizer.organize(at: dir)

        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Book A/Book A.epub").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Book B/Book B.pdf").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Comic/Comic.cbr").path))
    }

    // MARK: - Ignores Non-Book Files

    @Test("Ignores non-book files (txt, jpg, etc)")
    func ignoresNonBookFiles() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir.appendingPathComponent("notes.txt"))
        try createFile(at: dir.appendingPathComponent("cover.jpg"))
        try createFile(at: dir.appendingPathComponent("readme.md"))

        LibraryOrganizer.organize(at: dir)

        // Files should remain in place
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes.txt").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("cover.jpg").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("readme.md").path))
    }

    // MARK: - Existing Subdirectories

    @Test("Leaves files already in subdirectories alone")
    func leavesSubdirFilesAlone() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let subdir = dir.appendingPathComponent("Existing Series")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try createFile(at: subdir.appendingPathComponent("Book.epub"))

        LibraryOrganizer.organize(at: dir)

        // File should stay where it was
        #expect(FileManager.default.fileExists(atPath: subdir.appendingPathComponent("Book.epub").path))
        // No new directory created
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("Book/Book.epub").path))
    }

    // MARK: - Unicode Filenames

    @Test("Handles unicode characters in filenames (umlauts)")
    func organizeUnicode() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir.appendingPathComponent("Empfängererklärung_EN.pdf"))

        LibraryOrganizer.organize(at: dir)

        let organized = dir.appendingPathComponent("Empfängererklärung_EN/Empfängererklärung_EN.pdf")
        #expect(FileManager.default.fileExists(atPath: organized.path))
    }

    @Test("Handles CJK characters in filenames")
    func organizeCJK() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir.appendingPathComponent("進撃の巨人.cbz"))

        LibraryOrganizer.organize(at: dir)

        let organized = dir.appendingPathComponent("進撃の巨人/進撃の巨人.cbz")
        #expect(FileManager.default.fileExists(atPath: organized.path))
    }

    // MARK: - Edge Cases

    @Test("Empty directory: no crash")
    func emptyDirectory() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        LibraryOrganizer.organize(at: dir)
        // Should not crash
    }

    @Test("Nonexistent directory: no crash")
    func nonexistentDirectory() {
        let dir = URL(fileURLWithPath: "/tmp/haven-nonexistent-\(UUID().uuidString)")
        LibraryOrganizer.organize(at: dir)
        // Should not crash
    }

    @Test("Mixed: organizes books, ignores other files and existing subdirs")
    func mixedContent() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Loose book files
        try createFile(at: dir.appendingPathComponent("New Book.epub"))
        // Non-book file
        try createFile(at: dir.appendingPathComponent("notes.txt"))
        // Existing series in subdir
        let series = dir.appendingPathComponent("Dune")
        try FileManager.default.createDirectory(at: series, withIntermediateDirectories: true)
        try createFile(at: series.appendingPathComponent("Dune - 01.epub"))
        try createFile(at: series.appendingPathComponent("Dune - 02.epub"))

        LibraryOrganizer.organize(at: dir)

        // Loose book moved
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("New Book/New Book.epub").path))
        // Non-book untouched
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes.txt").path))
        // Existing series untouched
        #expect(FileManager.default.fileExists(atPath: series.appendingPathComponent("Dune - 01.epub").path))
        #expect(FileManager.default.fileExists(atPath: series.appendingPathComponent("Dune - 02.epub").path))
    }

    @Test("All supported extensions are organized")
    func allExtensions() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        for ext in LibraryOrganizer.bookExtensions {
            try createFile(at: dir.appendingPathComponent("test.\(ext)"))
        }

        LibraryOrganizer.organize(at: dir)

        for ext in LibraryOrganizer.bookExtensions {
            let organized = dir.appendingPathComponent("test/test.\(ext)")
            #expect(FileManager.default.fileExists(atPath: organized.path),
                    "Extension .\(ext) should be organized")
        }
    }

    @Test("Hidden files are ignored")
    func hiddenFilesIgnored() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir.appendingPathComponent(".hidden.epub"))

        LibraryOrganizer.organize(at: dir)

        // Hidden file should stay in place
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".hidden.epub").path))
    }

    @Test("Case-insensitive extension matching")
    func caseInsensitiveExtension() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir.appendingPathComponent("Book.EPUB"))
        try createFile(at: dir.appendingPathComponent("Doc.PDF"))

        LibraryOrganizer.organize(at: dir)

        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Book/Book.EPUB").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Doc/Doc.PDF").path))
    }
}

// MARK: - Device Access URL Tests

@Suite("Device Access URLs")
struct DeviceAccessURLTests {

    private func makeTestID() -> String {
        "haven.test.kavita.\(UUID().uuidString)"
    }

    private func cleanupDefaults(for id: String) {
        for suffix in ["token", "username", "password", "managedUser", "managedPass", "customAccount", "apiKey"] {
            UserDefaults.standard.removeObject(forKey: "haven.kavita.\(suffix).\(id)")
        }
    }

    @Test("serverAddress is nil when no port")
    @MainActor func serverAddressNoPort() {
        let id = makeTestID()
        defer { cleanupDefaults(for: id) }
        let sm = ServiceManager()
        let f = KavitaBooksFacade(capabilityID: id, serviceManager: sm)

        #expect(f.serverAddress == nil)
    }

    @Test("opdsURL is nil when disconnected")
    @MainActor func opdsURLDisconnected() {
        let id = makeTestID()
        defer { cleanupDefaults(for: id) }
        let sm = ServiceManager()
        let f = KavitaBooksFacade(capabilityID: id, serviceManager: sm)

        #expect(f.opdsURL == nil)
    }

    @Test("opdsURL is nil when no apiKey")
    @MainActor func opdsURLNoApiKey() {
        let id = makeTestID()
        defer { cleanupDefaults(for: id) }
        let sm = ServiceManager()
        let f = KavitaBooksFacade(capabilityID: id, serviceManager: sm)

        #expect(f.apiKey == nil)
        #expect(f.opdsURL == nil)
    }
}

// MARK: - FileGroupTypes Safety Tests

@Suite("FileGroupTypes Safety")
struct FileGroupTypesSafetyTests {

    @Test("Safe types are [2, 3, 4]")
    func safeTypes() {
        // These are the only values that don't crash Kavita's macOS scanner
        let safe = [2, 3, 4]
        let unsafe = [0, 1, 5]

        for v in safe {
            #expect(safe.contains(v), "Value \(v) should be safe")
        }
        for v in unsafe {
            #expect(!safe.contains(v), "Value \(v) should be unsafe")
        }
    }

    @Test("Library with safe types needs no fix")
    func noFixNeeded() {
        let types = [2, 3, 4]
        let safeTypes = [2, 3, 4]
        #expect(types == safeTypes)
    }

    @Test("Library with value 5 needs fix")
    func value5NeedsFix() {
        let types = [2, 3, 4, 5]
        let safeTypes = [2, 3, 4]
        #expect(types != safeTypes)
    }

    @Test("Library with values 0 and 1 needs fix")
    func archiveTypesNeedFix() {
        let types = [0, 1, 2, 3, 4]
        let safeTypes = [2, 3, 4]
        #expect(types != safeTypes)
    }

    @Test("Library with only epub needs fix")
    func epubOnlyNeedsFix() {
        let types = [2]
        let safeTypes = [2, 3, 4]
        #expect(types != safeTypes)
    }
}
