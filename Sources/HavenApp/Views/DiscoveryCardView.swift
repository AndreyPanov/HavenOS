import SwiftUI

/// Card for a capability in the Home overview.
/// Shows all capabilities — both added and available — with status indicator.
struct CapabilityCardView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let plugin: DiscoverablePlugin

    private var installedService: InstalledService? {
        serviceManager.installedServices.first { $0.id == plugin.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with status
            HStack(spacing: 10) {
                ServiceIconView(systemName: plugin.icon, imagePath: plugin.iconImagePath)

                Text(plugin.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                statusIndicator
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

            // Action row
            HStack {
                if let service = installedService {
                    // Already added — no action button needed, status is at top
                    if service.status == .running, serviceManager.hasNativeUI(for: service.id) {
                        Text("Open from sidebar")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else if serviceManager.activeCapabilityID == plugin.id {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(serviceManager.actionStatus ?? "Working...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Button("Add") {
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

    @ViewBuilder
    private var statusIndicator: some View {
        if let service = installedService {
            switch service.status {
            case .running:
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Online")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .stopped:
                HStack(spacing: 4) {
                    Circle()
                        .fill(.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text("Offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .installing:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Setting up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed:
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Error")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    HStack {
        CapabilityCardView(plugin: MockData.discoverablePlugins[0])
        CapabilityCardView(plugin: MockData.discoverablePlugins[0])
    }
    .environment(ServiceManager())
    .padding()
    .frame(width: 600)
}
