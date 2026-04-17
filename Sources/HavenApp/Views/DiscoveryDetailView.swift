import AppKit
import SwiftUI

struct DiscoveryDetailView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let plugin: DiscoverablePlugin

    /// Live installed service data (nil if not installed).
    private var installedService: InstalledService? {
        serviceManager.installedServices.first { $0.id == plugin.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    ServiceIconView(systemName: plugin.icon, imagePath: plugin.iconImagePath, size: 56)
                        .glassEffect(in: .rect(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        if let service = installedService {
                            StatusBadgeView(status: service.status)
                        }
                    }

                    Spacer()

                    if plugin.isInstalled {
                        if let service = installedService, service.status == .running,
                           let url = service.localURL, let openURL = URL(string: url) {
                            Button("Open in Browser", systemImage: "globe") {
                                NSWorkspace.shared.open(openURL)
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                        }
                    } else {
                        Button("Install") {
                            Task { await serviceManager.installService(capabilityID: plugin.id) }
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(serviceManager.isPerformingAction)
                    }
                }

                // Screenshots
                if !plugin.screenshotPaths.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(plugin.screenshotPaths, id: \.self) { path in
                                ScreenshotImage(path: path)
                            }
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quinary)
                        .frame(height: 180)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: plugin.icon)
                                    .font(.system(size: 48))
                                    .foregroundStyle(.tertiary)
                                Text("Preview")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                }

                // About
                GroupBox("About") {
                    Text(plugin.fullDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }

                // Details
                GroupBox("Details") {
                    VStack(spacing: 0) {
                        PluginDetailRow(label: "Type", value: plugin.notes.first ?? "Service")
                        if let service = installedService {
                            Divider().padding(.vertical, 6)
                            PluginDetailRow(label: "Status", value: service.status.rawValue)
                            if let port = service.port {
                                Divider().padding(.vertical, 6)
                                PluginDetailRow(label: "Port", value: "\(port)")
                            }
                            if let url = service.localURL {
                                Divider().padding(.vertical, 6)
                                PluginDetailRow(label: "Address", value: url)
                            }
                        }
                    }
                    .padding(4)
                }

                // Features
                if !plugin.notes.isEmpty {
                    GroupBox("Features") {
                        HStack(spacing: 8) {
                            ForEach(plugin.notes, id: \.self) { note in
                                Label(note, systemImage: "checkmark")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(4)
                    }
                }

                // Settings preview
                GroupBox("Settings Preview") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Service-specific settings will be available after installation.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Actions
                if serviceManager.activeCapabilityID == plugin.id {
                    GroupBox {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                            Text(serviceManager.actionStatus ?? "Working…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(4)
                    }
                } else if let service = installedService {
                    // Installed: show full service controls
                    HStack(spacing: 12) {
                        if service.status == .running {
                            Button("Stop", systemImage: "stop.circle") {
                                Task { await serviceManager.stopService(capabilityID: plugin.id) }
                            }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                            .disabled(serviceManager.isPerformingAction)

                            Button("Restart", systemImage: "arrow.clockwise") {
                                Task {
                                    await serviceManager.stopService(capabilityID: plugin.id)
                                    await serviceManager.startService(capabilityID: plugin.id)
                                }
                            }
                            .buttonStyle(.glass)
                            .controlSize(.large)
                            .disabled(serviceManager.isPerformingAction)
                        } else {
                            Button("Start", systemImage: "play.circle") {
                                Task { await serviceManager.startService(capabilityID: plugin.id) }
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .disabled(serviceManager.isPerformingAction)
                        }

                        Spacer()

                        Button("Stop & Remove", systemImage: "trash", role: .destructive) {
                            Task { await serviceManager.uninstallService(capabilityID: plugin.id) }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .disabled(serviceManager.isPerformingAction)
                    }
                } else {
                    // Not installed
                    HStack {
                        Button("Install", systemImage: "plus.circle") {
                            Task { await serviceManager.installService(capabilityID: plugin.id) }
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(serviceManager.isPerformingAction)
                        Spacer()
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(plugin.name)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ScreenshotImage: View {
    let path: String

    var body: some View {
        if let url = URL(string: path), url.scheme == "https" || url.scheme == "http" {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                case .failure:
                    Color.clear.frame(width: 0, height: 0)
                default:
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quinary)
                        .frame(width: 280, height: 180)
                        .overlay { ProgressView() }
                }
            }
        } else if let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct PluginDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }
}

#Preview {
    NavigationStack {
        DiscoveryDetailView(plugin: MockData.discoverablePlugins[0])
    }
    .environment(ServiceManager())
    .frame(width: 600, height: 700)
}
