import SwiftUI

struct DiscoveryCardView: View {
    let plugin: DiscoverablePlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: plugin.icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)

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
                    Button("Open") {}
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else {
                    Button("Install") {}
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                Spacer()

                Button("Learn More") {}
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

#Preview {
    HStack {
        DiscoveryCardView(plugin: MockData.discoverablePlugins[0])
        DiscoveryCardView(plugin: MockData.discoverablePlugins[0])
    }
    .padding()
    .frame(width: 600)
}
