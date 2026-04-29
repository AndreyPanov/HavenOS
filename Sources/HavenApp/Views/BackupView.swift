import SwiftUI
import AppKit
import HavenBackup

struct BackupView: View {
    @Environment(HavenSettingsModel.self) private var settings
    @Environment(ServiceManager.self) private var serviceManager

    var body: some View {
        @Bindable var settings = settings

        Form {
            // Health overview
            Section("Status") {
                backupHealthView
            }

            // Per-capability backup destinations
            Section("Capabilities") {
                if serviceManager.installedServices.isEmpty {
                    Text("No capabilities installed yet. Add a capability to configure backup.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(serviceManager.installedServices, id: \.id) { service in
                        CapabilityBackupRow(service: service)
                    }
                }
            }

            // Schedule
            Section("Schedule") {
                Picker("Automatic Backup", selection: Binding(
                    get: { settings.backupSettings.schedule },
                    set: { newValue in
                        settings.backupSettings.schedule = newValue
                    }
                )) {
                    Text("Daily").tag(BackupSchedule.daily)
                    Text("Weekly").tag(BackupSchedule.weekly)
                    Text("Monthly").tag(BackupSchedule.monthly)
                    Text("Manual Only").tag(BackupSchedule.manual)
                }

                HStack(spacing: 12) {
                    Button("Back Up Now") {
                        Task {
                            await serviceManager.performBackup(settings: settings.backupSettings)
                            settings.backupSettings = BackupSettings.load()
                        }
                    }
                    .disabled(!settings.backupSettings.isConfigured || serviceManager.isBackingUp)

                    if serviceManager.isBackingUp {
                        ProgressView()
                            .controlSize(.small)
                        if let status = serviceManager.backupStatus {
                            Text(status)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Backup")
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var backupHealthView: some View {
        let health = serviceManager.backupHealth

        if serviceManager.isBackingUp {
            Label("Backup in progress\u{2026}",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.callout)
                .foregroundStyle(.blue)
        } else {
            switch health.status {
            case .notConfigured:
                Label("Choose a backup folder for each capability to protect your data",
                      systemImage: "externaldrive.badge.questionmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)

            case .neverRun:
                Label("Backup configured but hasn't run yet",
                      systemImage: "clock.badge.questionmark")
                    .font(.callout)
                    .foregroundStyle(.orange)

            case .healthy:
                if let date = health.lastBackupDate {
                    Label("Last backup: \(date.formatted(.relative(presentation: .named)))",
                          systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.green)
                }

            case .overdue(let days):
                Label("Backup overdue by \(days) day\(days == 1 ? "" : "s")",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)

            case .warning(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)

            case .failed(let message):
                Label(message, systemImage: "xmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }

        if !serviceManager.installedServices.isEmpty {
            ProtectionStatusView(health: health)
                .padding(.top, 4)
        }
    }
}

/// A row for one capability showing its backup destination with a folder picker.
private struct CapabilityBackupRow: View {
    let service: InstalledService
    @Environment(HavenSettingsModel.self) private var settings
    @Environment(ServiceManager.self) private var serviceManager

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let path = settings.backupSettings.capabilityDestinations[service.id] {
                    Text(path)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button("Change\u{2026}") {
                        chooseFolder()
                    }
                    .controlSize(.small)

                    Button {
                        settings.backupSettings.removeDestination(for: service.id)
                        serviceManager.refreshBackupHealth(settings: settings.backupSettings)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove backup destination")
                } else {
                    Text("Not configured")
                        .foregroundStyle(.tertiary)

                    Button("Choose\u{2026}") {
                        chooseFolder()
                    }
                    .controlSize(.small)
                }
            }
        } label: {
            Label(serviceManager.userFacingName(for: service), systemImage: service.icon)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a backup folder for \(serviceManager.userFacingName(for: service))"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.backupSettings.setDestination(url.path, for: service.id)
        serviceManager.refreshBackupHealth(settings: settings.backupSettings)
    }
}

#Preview {
    BackupView()
        .environment(HavenSettingsModel())
        .environment(ServiceManager())
        .frame(width: 600, height: 500)
}
