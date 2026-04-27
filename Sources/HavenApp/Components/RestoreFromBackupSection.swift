import SwiftUI
import AppKit
import HavenBackup

/// A card shown on capability tabs offering to restore media files from a backup.
///
/// Appears in the "empty" state or as a toolbar menu item when the capability
/// has a backup destination configured.
struct RestoreFromBackupSection: View {
    @Environment(ServiceManager.self) private var serviceManager
    @Environment(HavenSettingsModel.self) private var settings

    let capabilityID: String
    let libraryPath: String?
    let label: String

    @State private var isRestoring = false
    @State private var restoreError: String?
    @State private var restoreComplete = false

    var body: some View {
        if let destPath = settings.backupSettings.capabilityDestinations[capabilityID] {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Restore from Backup", systemImage: "arrow.counterclockwise")
                        .font(.callout)
                        .fontWeight(.medium)

                    Text("A backup is configured for this library. You can copy your media files back from the backup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if isRestoring {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Restoring files…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else if restoreComplete {
                        Label("Files restored successfully.", systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(.green)
                    } else if let error = restoreError {
                        Label(error, systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Restore Files\u{2026}") {
                        restoreFiles(backupPath: destPath)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isRestoring || libraryPath == nil)
                }
                .padding(4)
            }
        }
    }

    private func restoreFiles(backupPath: String) {
        guard let libPath = libraryPath else { return }

        let expanded = (backupPath as NSString).expandingTildeInPath
        let backupURL = URL(fileURLWithPath: expanded)
        let expandedLib = (libPath as NSString).expandingTildeInPath
        let libraryURL = URL(fileURLWithPath: expandedLib)

        isRestoring = true
        restoreError = nil
        restoreComplete = false

        Task {
            do {
                try await serviceManager.restoreFiles(
                    for: capabilityID,
                    from: backupURL,
                    to: libraryURL
                )
                restoreComplete = true
            } catch {
                restoreError = error.localizedDescription
            }
            isRestoring = false
        }
    }
}
