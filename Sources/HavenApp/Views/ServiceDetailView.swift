import SwiftUI

struct ServiceDetailView: View {
    let service: InstalledService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    Image(systemName: service.icon)
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, height: 56)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        StatusBadgeView(status: service.status)
                    }

                    Spacer()
                }

                // Description
                GroupBox("About") {
                    Text(service.serviceDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }

                // Info
                GroupBox("Details") {
                    VStack(spacing: 0) {
                        ServiceDetailRow(label: "Status", value: service.status.rawValue)
                        Divider().padding(.vertical, 6)
                        if let url = service.localURL {
                            ServiceDetailRow(label: "Local Address", value: url)
                            Divider().padding(.vertical, 6)
                        }
                        if let port = service.port {
                            ServiceDetailRow(label: "Port", value: "\(port)")
                            Divider().padding(.vertical, 6)
                        }
                        ServiceDetailRow(label: "Data Path", value: service.dataPath)
                    }
                    .padding(4)
                }

                // Logs preview
                GroupBox("Recent Activity") {
                    VStack(alignment: .leading, spacing: 4) {
                        LogLine(time: "10:32:01", message: "Service started successfully")
                        LogLine(time: "10:32:00", message: "Initializing service...")
                        LogLine(time: "10:31:58", message: "Loading configuration")
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Action buttons
                HStack(spacing: 12) {
                    if service.status == .running {
                        Button("Open", systemImage: "arrow.up.forward.square") {}
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        Button("Stop", systemImage: "stop.circle") {}
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        Button("Restart", systemImage: "arrow.clockwise") {}
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    } else {
                        Button("Start", systemImage: "play.circle") {}
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }

                    Spacer()

                    Button("Remove", systemImage: "trash", role: .destructive) {}
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
            .padding(24)
        }
        .navigationTitle(service.name)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }
}

private struct ServiceDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

private struct LogLine: View {
    let time: String
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Text(time)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        ServiceDetailView(service: MockData.installedServices[0])
    }
    .frame(width: 600, height: 700)
}
