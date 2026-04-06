import AppKit
import SwiftUI

struct ServiceCardView: View {
    @Environment(ServiceManager.self) private var serviceManager
    @State private var showingInfo = false
    let service: InstalledService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: icon + name + status
            HStack(spacing: 10) {
                Image(systemName: service.icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)

                Text(service.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                StatusBadgeView(status: service.status)
            }

            // Description
            Text(service.serviceDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                if service.status == .running {
                    CardActionButton(title: "Stop", icon: "stop.circle") {
                        Task { await serviceManager.stopService(capabilityID: service.id) }
                    }
                    .disabled(serviceManager.isPerformingAction)

                    if let url = service.localURL,
                       let openURL = URL(string: url) {
                        CardActionButton(title: "Open", icon: "globe") {
                            NSWorkspace.shared.open(openURL)
                        }
                    }
                } else {
                    CardActionButton(title: "Start", icon: "play.circle") {
                        Task { await serviceManager.startService(capabilityID: service.id) }
                    }
                    .disabled(serviceManager.isPerformingAction)
                }

                Spacer()

                if service.port != nil {
                    Button {
                        showingInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showingInfo, arrowEdge: .bottom) {
                        ServiceInfoPopover(service: service)
                    }
                }

                Menu {
                    Button("Restart", systemImage: "arrow.clockwise") {
                        Task {
                            await serviceManager.stopService(capabilityID: service.id)
                            await serviceManager.startService(capabilityID: service.id)
                        }
                    }
                    Divider()
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        Task { await serviceManager.uninstallService(capabilityID: service.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(serviceManager.isPerformingAction)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .buttonStyle(.glass)
        .controlSize(.small)
    }
}

private struct ServiceInfoPopover: View {
    let service: InstalledService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let port = service.port {
                InfoRow(label: "Port", value: "\(port)")
            }
            if let url = service.localURL {
                InfoRow(label: "Address", value: url)
            }
        }
        .font(.callout)
        .padding(12)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    ServiceCardView(service: MockData.installedServices[0])
        .environment(ServiceManager())
        .frame(width: 300)
        .padding()
}
