import AppKit
import SwiftUI
import HavenCore
import HavenFacade

struct ServiceDetailView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let serviceID: String

    private var service: InstalledService {
        serviceManager.installedServices.first { $0.id == serviceID }
            ?? InstalledService(id: serviceID, name: serviceID, serviceDescription: "", icon: "shippingbox", iconImagePath: nil, status: .stopped, port: nil, dataPath: "", instructions: nil, onboarding: nil)
    }

    private var facade: (any CapabilityFacade)? {
        serviceManager.facade(for: serviceID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    ServiceIconView(systemName: service.icon, imagePath: service.iconImagePath, size: 56)
                        .glassEffect(in: .rect(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        StatusBadgeView(status: service.status)
                        if showsUpdateBadge {
                            ServiceUpdateBadgeView(
                                state: serviceManager.updateState(for: serviceID)
                            )
                        }
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

                GroupBox("Updates") {
                    VStack(alignment: .leading, spacing: 12) {
                        let presentation = serviceManager.updatePresentation(for: serviceID)
                        HStack(spacing: 10) {
                            if presentation.showsProgress {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: presentation.systemImage)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(presentation.title)
                                    .font(.callout)
                                if let detail = presentation.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Button {
                                Task {
                                    await serviceManager.checkForUpdates(
                                        capabilityID: serviceID
                                    )
                                }
                            } label: {
                                Label("Check", systemImage: "arrow.down.circle")
                            }
                            .disabled(serviceManager.isPerformingAction)

                            if canRunUpdate {
                                Button {
                                    Task {
                                        await serviceManager.updateService(
                                            capabilityID: serviceID
                                        )
                                    }
                                } label: {
                                    Label(updateButtonTitle, systemImage: "arrow.clockwise")
                                }
                                .disabled(serviceManager.isPerformingAction)
                            }

                            if let logsURL = serviceManager.logsURL(for: serviceID) {
                                Button {
                                    NSWorkspace.shared.open(logsURL)
                                } label: {
                                    Label("Logs", systemImage: "doc.text.magnifyingglass")
                                }
                            }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                    .padding(4)
                }

                // Setup Guide (from resolved onboarding)
                if let onboarding = service.onboarding, !onboarding.steps.isEmpty {
                    GroupBox("Setup Guide") {
                        OnboardingStepsView(steps: onboarding.steps)
                            .padding(4)
                    }
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

                // Action buttons (driven by facade)
                if let facade {
                    FacadeActionBar(facade: facade, isPerformingAction: serviceManager.isPerformingAction)
                }
            }
            .padding(24)
        }
        .navigationTitle(service.name)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var showsUpdateBadge: Bool {
        switch serviceManager.updateState(for: serviceID) {
        case .idle, .upToDate:
            false
        default:
            true
        }
    }

    private var canRunUpdate: Bool {
        let state = serviceManager.updateState(for: serviceID)
        if case .updateAvailable = state { return true }
        return serviceManager.updatePresentation(for: serviceID).allowsRetry
    }

    private var updateButtonTitle: String {
        serviceManager.updatePresentation(for: serviceID).allowsRetry
            ? "Retry"
            : "Update"
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
        ServiceDetailView(serviceID: MockData.installedServices[0].id)
    }
    .environment(ServiceManager())
    .frame(width: 600, height: 700)
}
