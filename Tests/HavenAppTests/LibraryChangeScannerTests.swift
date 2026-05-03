import Foundation
import Testing
@testable import HavenAppKit

@Suite("LibraryChangeScanner")
struct LibraryChangeScannerTests {

    @Test("First daily check stores a baseline without rescanning")
    func firstCheckStoresBaseline() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = try makeLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(named: "Book.epub", in: root, contents: "one")

        let prefix = "haven.test.dailyScan.\(UUID().uuidString)"
        let signature = LibraryChangeScanner.contentSignature(for: [root.path])
        let decision = LibraryChangeScanner.evaluateDailyRescan(
            contentSignature: signature,
            keyPrefix: prefix,
            defaults: defaults,
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(decision.shouldRescan == false)
        #expect(defaults.string(forKey: LibraryChangeScanner.signatureKey(prefix: prefix)) == signature)
    }

    @Test("Changed content triggers once after the daily interval")
    func changedContentTriggersOnceDaily() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = try makeLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(named: "Movie.mkv", in: root, contents: "one")

        let prefix = "haven.test.dailyScan.\(UUID().uuidString)"
        let t0 = Date(timeIntervalSince1970: 1_000)
        let baseline = LibraryChangeScanner.contentSignature(for: [root.path])
        _ = LibraryChangeScanner.evaluateDailyRescan(
            contentSignature: baseline,
            keyPrefix: prefix,
            defaults: defaults,
            now: t0
        )

        try writeFile(named: "New Movie.mkv", in: root, contents: "two")
        let changed = LibraryChangeScanner.contentSignature(for: [root.path])
        #expect(changed != baseline)

        let tooSoon = LibraryChangeScanner.evaluateDailyRescan(
            contentSignature: changed,
            keyPrefix: prefix,
            defaults: defaults,
            now: t0.addingTimeInterval(60 * 60)
        )
        #expect(tooSoon.shouldRescan == false)

        let due = LibraryChangeScanner.evaluateDailyRescan(
            contentSignature: changed,
            keyPrefix: prefix,
            defaults: defaults,
            now: t0.addingTimeInterval(LibraryChangeScanner.dailyInterval + 1)
        )
        #expect(due.shouldRescan == true)

        LibraryChangeScanner.markRescanTriggered(
            contentSignature: changed,
            keyPrefix: prefix,
            defaults: defaults,
            now: t0.addingTimeInterval(LibraryChangeScanner.dailyInterval + 1)
        )

        let sameDay = LibraryChangeScanner.evaluateDailyRescan(
            contentSignature: changed,
            keyPrefix: prefix,
            defaults: defaults,
            now: t0.addingTimeInterval(LibraryChangeScanner.dailyInterval + 60 * 60)
        )
        #expect(sameDay.shouldRescan == false)
    }

    @Test("Unmarked changed content is retried on the next daily check")
    func failedRescanRetriesNextDay() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let root = try makeLibraryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(named: "Book.epub", in: root, contents: "one")

        let prefix = "haven.test.dailyScan.\(UUID().uuidString)"
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = LibraryChangeScanner.evaluateDailyRescan(
            contentSignature: LibraryChangeScanner.contentSignature(for: [root.path]),
            keyPrefix: prefix,
            defaults: defaults,
            now: t0
        )

        try writeFile(named: "Another Book.epub", in: root, contents: "two")
        let changed = LibraryChangeScanner.contentSignature(for: [root.path])

        let firstDue = LibraryChangeScanner.evaluateDailyRescan(
            contentSignature: changed,
            keyPrefix: prefix,
            defaults: defaults,
            now: t0.addingTimeInterval(LibraryChangeScanner.dailyInterval + 1)
        )
        #expect(firstDue.shouldRescan == true)

        let nextDue = LibraryChangeScanner.evaluateDailyRescan(
            contentSignature: changed,
            keyPrefix: prefix,
            defaults: defaults,
            now: t0.addingTimeInterval((2 * LibraryChangeScanner.dailyInterval) + 2)
        )
        #expect(nextDue.shouldRescan == true)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "LibraryChangeScannerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeLibraryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HavenLibraryChangeScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeFile(named name: String, in root: URL, contents: String) throws {
        let url = root.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
    }
}
