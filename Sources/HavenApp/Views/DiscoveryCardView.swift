import SwiftUI

struct DiscoveryCardView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let plugin: DiscoverablePlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                ServiceIconView(systemName: plugin.icon, imagePath: plugin.iconImagePath)

                Text(plugin.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if plugin.isInstalled {
                    Text("Installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }

            // Summary
            Text(plugin.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Notes
            if !plugin.notes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(plugin.notes, id: \.self) { note in
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }
            }

            Divider()

            // Actions
            HStack {
                if plugin.isInstalled {
                    Button("Installed") {}
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .disabled(true)
                } else {
                    Button("Install") {
                        Task { await serviceManager.installService(capabilityID: plugin.id) }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .disabled(serviceManager.isPerformingAction)
                }

                Spacer()
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    HStack {
        DiscoveryCardView(plugin: MockData.discoverablePlugins[0])
        DiscoveryCardView(plugin: MockData.discoverablePlugins[0])
    }
    .environment(ServiceManager())
    .padding()
    .frame(width: 600)
}
