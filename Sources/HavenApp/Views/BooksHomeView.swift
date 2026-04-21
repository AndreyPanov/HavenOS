import AppKit
import SwiftUI
import HavenFacade

/// Native Books capability screen.
///
/// Shows library status, series count, and actions — all inside Haven.
/// "Open in Kavita" is a secondary action, not the primary experience.
struct BooksHomeView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let facade: any BooksFacade
    @State private var showingConnectSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(spacing: 16) {
                    ServiceIconView(
                        systemName: service?.icon ?? "books.vertical",
                        imagePath: service?.iconImagePath,
                        size: 56
                    )
                    .glassEffect(in: .rect(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Books")
                            .font(.title2)
                            .fontWeight(.semibold)
                        StatusBadgeView(status: serviceStatus)
                    }

                    Spacer()
                }

                // Main content based on state
                switch facade.state {
                case .idle, .error:
                    stoppedView
                case .starting:
                    startingView
                case .ready, .degraded:
                    switch facade.connectionState {
                    case .disconnected:
                        connectPromptView
                    case .connecting:
                        connectingView
                    case .connected:
                        connectedView
                    case .failed(let message):
                        connectionFailedView(message: message)
                    }
                }

                // Action bar
                FacadeActionBar(facade: facade, isPerformingAction: serviceManager.isPerformingAction)
            }
            .padding(24)
        }
        .navigationTitle("Books")
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, alignment: .center)
        .sheet(isPresented: $showingConnectSheet) {
            BooksConnectSheet(facade: facade)
        }
    }

    // MARK: - State Views

    private var stoppedView: some View {
        GroupBox {
            VStack(spacing: 16) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Your library is stopped")
                    .font(.headline)
                Text("Start the service to access your book library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Start Library", systemImage: "play.circle") {
                    Task { try? await facade.perform(.start) }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(serviceManager.isPerformingAction)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    private var startingView: some View {
        GroupBox {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Starting your library…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(8)
        }
    }

    private var connectPromptView: some View {
        GroupBox {
            VStack(spacing: 16) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Connect to your library")
                    .font(.headline)
                Text("Enter your Kavita credentials so Haven can show your library here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Connect", systemImage: "link") {
                    showingConnectSheet = true
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    private var connectingView: some View {
        GroupBox {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(8)
        }
    }

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Library info card
            GroupBox("Library") {
                VStack(spacing: 0) {
                    if let lib = facade.library {
                        DetailRow(label: "Location", value: lib.libraryPath)
                        Divider().padding(.vertical, 6)
                        DetailRow(
                            label: "Series",
                            value: facade.seriesCount.map { "\($0)" } ?? "—"
                        )
                    }
                    if let username = facade.connectedUsername {
                        Divider().padding(.vertical, 6)
                        DetailRow(label: "Connected as", value: username)
                    }
                }
                .padding(4)
            }

            // Connection management
            HStack {
                if let username = facade.connectedUsername {
                    Label("Connected as \(username)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Disconnect", systemImage: "link.badge.plus") {
                    facade.disconnect()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Setup guide (from onboarding)
            if let onboarding = service?.onboarding, !onboarding.steps.isEmpty {
                GroupBox("Setup Guide") {
                    OnboardingStepsView(steps: onboarding.steps)
                        .padding(4)
                }
            }
        }
    }

    private func connectionFailedView(message: String) -> some View {
        GroupBox {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text("Connection failed")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        showingConnectSheet = true
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    Button("Dismiss") {
                        facade.disconnect()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    // MARK: - Helpers

    private var service: InstalledService? {
        serviceManager.installedServices.first { $0.id == facade.capabilityID }
    }

    private var serviceStatus: ServiceStatus {
        service?.status ?? .stopped
    }
}

private struct DetailRow: View {
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
