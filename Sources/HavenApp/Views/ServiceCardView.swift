import SwiftUI

struct ServiceCardView: View {
    let service: InstalledService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: icon + name + status
            HStack(spacing: 10) {
                Image(systemName: service.icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.headline)
                        .lineLimit(1)
                    if let port = service.port {
                        Text("Port \(port)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                StatusBadgeView(status: service.status)
            }

            // Description
            Text(service.serviceDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Local URL
            if let url = service.localURL {
                Text(url)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                if service.status == .running {
                    CardActionButton(title: "Open", icon: "arrow.up.forward.square") {}
                    CardActionButton(title: "Stop", icon: "stop.circle") {}
                } else {
                    CardActionButton(title: "Start", icon: "play.circle") {}
                }

                Spacer()

                Menu {
                    Button("Open in Browser", systemImage: "safari") {}
                    Button("Restart", systemImage: "arrow.clockwise") {}
                    Divider()
                    Button("Remove", systemImage: "trash", role: .destructive) {}
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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

private struct CardActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

#Preview {
    ServiceCardView(service: MockData.installedServices[0])
        .frame(width: 300)
        .padding()
}
