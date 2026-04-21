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
