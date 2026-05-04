import SwiftUI
import HavenBackup
import os

private let log = Logger(subsystem: "com.haven", category: "Settings")

@Observable
package class HavenSettingsModel {
    var dataDirectory = "~/.haven"
    var baseDirectory = "~/.haven"

    let version = "0.1.1"
    let buildNumber = "2"

    // MARK: - Catalog

    /// Local catalog folder path, persisted in UserDefaults.
    package var catalogFolder: String {
        didSet {
            UserDefaults.standard.set(catalogFolder, forKey: "catalogFolderPath")
            log.info("Catalog folder changed to: \(self.catalogFolder)")
        }
    }

    /// The catalog folder as a resolved file URL (expands ~).
    package var catalogFolderURL: URL {
        URL(fileURLWithPath: NSString(string: catalogFolder).expandingTildeInPath)
    }

    static let defaultCatalogFolder = "~/.haven/Catalog"

    // MARK: - Backup

    /// Backup configuration, persisted in UserDefaults.
    package var backupSettings: BackupSettings {
        didSet {
            backupSettings.save()
            log.info("Backup settings updated")
        }
    }

    package init() {
        self.catalogFolder = UserDefaults.standard.string(forKey: "catalogFolderPath")
            ?? Self.defaultCatalogFolder
        self.backupSettings = BackupSettings.load()
    }
}
