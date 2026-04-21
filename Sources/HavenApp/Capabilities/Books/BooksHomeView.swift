import AppKit
import SwiftUI
import HavenFacade

/// Native Books capability screen.
///
/// Uses ``BooksFacade`` (protocol) for all state. The only concrete
/// type reference is the optional downcast to ``KavitaBooksFacade``
/// for the connect sheet — a future backend that doesn't need auth
/// would skip that entirely via `setupState == .ready`.
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
                    switch facade.setupState {
                    case .needsSetup:
                        setupPromptView
                    case .settingUp:
                        settingUpView
                    case .ready:
                        readyView
                    case .failed(let message):
                        setupFailedView(message: message)
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
            if let kavita = facade as? KavitaBooksFacade {
                BooksConnectSheet(facade: kavita)
            } else if let mock = facade as? MockBooksFacade {
                MockBooksSetupSheet(facade: mock)
            }
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

    private var setupPromptView: some View {
        GroupBox {
            VStack(spacing: 16) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Connect to your library")
                    .font(.headline)
                Text("Sign in so Haven can show your library here.")
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

    private var settingUpView: some View {
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

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Library info card
            GroupBox("Library") {
                VStack(spacing: 0) {
                    if let lib = facade.library {
                        DetailRow(label: "Location", value: lib.libraryPath)
                        if let count = lib.itemCount {
                            Divider().padding(.vertical, 6)
                            DetailRow(label: "Items", value: "\(count)")
                        }
                    }
                    // Kavita-specific: show connected user
                    if let kavita = facade as? KavitaBooksFacade,
                       let username = kavita.connectedUsername {
                        Divider().padding(.vertical, 6)
                        DetailRow(label: "Connected as", value: username)
                    }
                }
                .padding(4)
            }

            // Backend-specific: disconnect
            if let kavita = facade as? KavitaBooksFacade,
               let username = kavita.connectedUsername {
                HStack {
                    Label("Connected as \(username)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Disconnect", systemImage: "link.badge.plus") {
                        kavita.disconnect()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if let mock = facade as? MockBooksFacade, mock.isConnected {
                HStack {
                    Label("Connected via API key", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Disconnect", systemImage: "link.badge.plus") {
                        mock.disconnect()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
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

    private func setupFailedView(message: String) -> some View {
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
                        if let kavita = facade as? KavitaBooksFacade {
                            kavita.disconnect()
                        } else if let mock = facade as? MockBooksFacade {
                            mock.disconnect()
                        }
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
