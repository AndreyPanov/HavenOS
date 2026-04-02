import SwiftUI

struct DiscoveryDetailView: View {
    let plugin: DiscoverablePlugin

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    Image(systemName: plugin.icon)
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 56)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(plugin.category.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if plugin.isInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else {
                        Button("Install") {}
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }

                // Screenshot placeholder
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary)
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
                        PluginDetailRow(label: "Category", value: plugin.category.rawValue)
                        Divider().padding(.vertical, 6)
                        PluginDetailRow(label: "Type", value: plugin.notes.first ?? "Service")
                        if plugin.isInstalled {
                            Divider().padding(.vertical, 6)
                            PluginDetailRow(label: "Status", value: "Installed")
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
                HStack {
                    if plugin.isInstalled {
                        Button("Open") {}
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        Button("Remove", role: .destructive) {}
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    } else {
                        Button("Install", systemImage: "plus.circle") {}
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                    Spacer()
                }
            }
            .padding(24)
        }
        .navigationTitle(plugin.name)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
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
    .frame(width: 600, height: 700)
}
