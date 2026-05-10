import AppKit
import SwiftUI
import HavenBackup

package struct HavenStatusMenu: View {
    @Environment(HavenSettingsModel.self) private var settings
    @Environment(ServiceManager.self) private var serviceManager
    @Environment(LoginItemManager.self) private var loginItemManager
    @Environment(\.openWindow) private var openWindow

    package init() {}

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                openHaven()
            } label: {
                menuActionLabel("Open HavenOS", systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            Toggle(isOn: Binding(
                get: { loginItemManager.isOpenAtLogin },
                set: { loginItemManager.setOpenAtLogin($0) }
            )) {
                Label("Open at Login", systemImage: "power")
                    .font(.body.weight(.medium))
            }
            .toggleStyle(.checkbox)
            .padding(.vertical, 8)

            if let status = loginItemManager.statusDescription {
                statusRow(status, systemImage: "info.circle", color: .secondary)
            }

            if let error = loginItemManager.lastError {
                statusRow(error, systemImage: "exclamationmark.triangle", color: .red)
            }

            Divider()
                .padding(.vertical, 8)

            sectionTitle("Capabilities")

            if serviceManager.installedServices.isEmpty {
                statusRow("No capabilities installed", systemImage: "circle.dashed", color: .secondary)
            } else {
                ForEach(serviceManager.installedServices) { service in
                    statusRow(
                        "\(serviceManager.userFacingName(for: service)): \(service.status.rawValue)",
                        systemImage: service.status.systemImage,
                        color: service.status.menuColor
                    )
                }
            }

            Divider()
                .padding(.vertical, 8)

            sectionTitle("Backup")

            statusRow(
                backupStatusText,
                systemImage: backupSystemImage,
                color: backupColor
            )

            if let detail = backupDetailText {
                statusRow(detail, systemImage: "clock", color: .primary)
            }

            Button {
                Task {
                    await backupNow()
                }
            } label: {
                menuActionLabel(
                    serviceManager.isBackingUp ? "Backing Up..." : "Back Up Now",
                    systemImage: "externaldrive.badge.plus"
                )
            }
            .buttonStyle(.plain)
            .disabled(!settings.backupSettings.isConfigured || serviceManager.isBackingUp)

            Divider()
                .padding(.vertical, 8)

            Button {
                Task {
                    await refreshMenuData()
                }
            } label: {
                menuActionLabel("Refresh Status", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                menuActionLabel("Quit HavenOS", systemImage: "power.circle")
            }
            .buttonStyle(.plain)
        }
        .frame(width: 280, alignment: .leading)
        .padding(14)
        .onAppear {
            Task {
                await refreshMenuData()
            }
        }
    }

    private func openHaven() {
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func refreshMenuData() async {
        settings.backupSettings = BackupSettings.load()
        serviceManager.refresh()
        serviceManager.refreshBackupHealth(settings: settings.backupSettings)
        loginItemManager.refresh()
        await serviceManager.refreshRuntimeStatuses()
    }

    private func backupNow() async {
        await serviceManager.performBackup(settings: settings.backupSettings)
        settings.backupSettings = BackupSettings.load()
        serviceManager.refreshBackupHealth(settings: settings.backupSettings)
        await serviceManager.refreshRuntimeStatuses()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
    }

    private func statusRow(
        _ title: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 18)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func menuActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }

    private var backupStatusText: String {
        if serviceManager.isBackingUp {
            return serviceManager.backupStatus ?? "Backup in progress"
        }

        switch serviceManager.backupHealth.status {
        case .notConfigured:
            return "Backup not configured"
        case .neverRun:
            return "Backup configured, never run"
        case .healthy:
            return "Backup healthy"
        case .overdue(let days):
            return "Backup overdue by \(days) day\(days == 1 ? "" : "s")"
        case .warning(let message):
            return message
        case .failed(let message):
            return message
        }
    }

    private var backupDetailText: String? {
        if serviceManager.isBackingUp {
            return nil
        }

        if let date = serviceManager.backupHealth.lastBackupDate {
            return "Last backup: \(date.formatted(.relative(presentation: .named)))"
        }

        let configured = serviceManager.backupHealth.configuredCount
        if configured > 0 {
            return "\(configured) configured, no backup yet"
        }

        return nil
    }

    private var backupSystemImage: String {
        switch serviceManager.backupHealth.status {
        case .notConfigured:
            return "externaldrive.badge.questionmark"
        case .neverRun:
            return "clock.badge.questionmark"
        case .healthy:
            return "checkmark.circle"
        case .overdue, .warning:
            return "exclamationmark.triangle"
        case .failed:
            return "xmark.circle"
        }
    }

    private var backupColor: Color {
        switch serviceManager.backupHealth.status {
        case .notConfigured:
            return .secondary
        case .neverRun, .overdue, .warning:
            return .orange
        case .healthy:
            return .green
        case .failed:
            return .red
        }
    }
}

private extension ServiceStatus {
    var menuColor: Color {
        switch self {
        case .running:
            return .green
        case .stopped:
            return .secondary
        case .failed:
            return .red
        case .installing:
            return .orange
        }
    }
}

#Preview {
    HavenStatusMenu()
        .environment(HavenSettingsModel())
        .environment(ServiceManager())
        .environment(LoginItemManager())
}
