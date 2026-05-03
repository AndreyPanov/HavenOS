import Foundation

/// Tracks whether library folders have changed enough to justify a backend rescan.
///
/// This is intentionally metadata-based: Haven only needs to know whether files
/// were added, removed, or edited since the previous scan baseline.
package enum LibraryChangeScanner {
    package static let dailyInterval: TimeInterval = 24 * 60 * 60
    package static let defaultCheckInterval: TimeInterval = 60 * 60

    package struct Decision: Sendable, Equatable {
        package let shouldRescan: Bool
        package let contentSignature: String?

        package init(shouldRescan: Bool, contentSignature: String?) {
            self.shouldRescan = shouldRescan
            self.contentSignature = contentSignature
        }
    }

    package static func contentSignature(for libraryPaths: [String]) -> String? {
        guard !libraryPaths.isEmpty else { return nil }

        let fm = FileManager.default
        var entries: [String] = []

        for rawPath in libraryPaths.sorted() {
            let expandedPath = (rawPath as NSString).expandingTildeInPath
            let root = URL(fileURLWithPath: expandedPath)

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                entries.append("missing|\(expandedPath)")
                continue
            }

            entries.append("root|\(expandedPath)")

            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                ]),
                    values.isRegularFile == true
                else {
                    continue
                }

                let relativePath = String(fileURL.path.dropFirst(root.path.count))
                let size = values.fileSize ?? 0
                let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
                entries.append("file|\(expandedPath)|\(relativePath)|\(size)|\(modified)")
            }
        }

        return stableDigest(for: entries)
    }

    package static func evaluateDailyRescan(
        contentSignature: String?,
        keyPrefix: String,
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        minimumInterval: TimeInterval = dailyInterval
    ) -> Decision {
        guard let contentSignature else {
            defaults.set(now, forKey: lastCheckKey(prefix: keyPrefix))
            return Decision(shouldRescan: false, contentSignature: nil)
        }

        if !isDailyCheckDue(
            keyPrefix: keyPrefix,
            defaults: defaults,
            now: now,
            minimumInterval: minimumInterval
        ) {
            return Decision(shouldRescan: false, contentSignature: contentSignature)
        }

        defaults.set(now, forKey: lastCheckKey(prefix: keyPrefix))

        guard let previous = defaults.string(forKey: signatureKey(prefix: keyPrefix)) else {
            defaults.set(contentSignature, forKey: signatureKey(prefix: keyPrefix))
            return Decision(shouldRescan: false, contentSignature: contentSignature)
        }

        return Decision(
            shouldRescan: previous != contentSignature,
            contentSignature: contentSignature
        )
    }

    package static func markRescanTriggered(
        contentSignature: String?,
        keyPrefix: String,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) {
        guard let contentSignature else { return }
        defaults.set(contentSignature, forKey: signatureKey(prefix: keyPrefix))
        defaults.set(now, forKey: lastTriggeredKey(prefix: keyPrefix))
    }

    package static func isDailyCheckDue(
        keyPrefix: String,
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        minimumInterval: TimeInterval = dailyInterval
    ) -> Bool {
        guard let lastCheck = defaults.object(forKey: lastCheckKey(prefix: keyPrefix)) as? Date else {
            return true
        }
        return now.timeIntervalSince(lastCheck) >= minimumInterval
    }

    package static func clear(keyPrefix: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastCheckKey(prefix: keyPrefix))
        defaults.removeObject(forKey: lastTriggeredKey(prefix: keyPrefix))
        defaults.removeObject(forKey: signatureKey(prefix: keyPrefix))
    }

    package static func lastCheckKey(prefix: String) -> String {
        "\(prefix).dailyChangeCheckAt"
    }

    package static func lastTriggeredKey(prefix: String) -> String {
        "\(prefix).dailyChangeRescanAt"
    }

    package static func signatureKey(prefix: String) -> String {
        "\(prefix).contentSignature"
    }

    private static func stableDigest(for entries: [String]) -> String {
        let prime: UInt64 = 1_099_511_628_211
        var hash: UInt64 = 14_695_981_039_346_656_037

        for entry in entries.sorted() {
            for byte in entry.utf8 {
                hash ^= UInt64(byte)
                hash &*= prime
            }
            hash ^= 10
            hash &*= prime
        }

        return "v1:\(entries.count):\(String(format: "%016llx", hash))"
    }
}
