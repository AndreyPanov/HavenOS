import AppKit
import SwiftUI
import HavenFacade

/// Native Books capability screen.
///
/// State-driven UI that adapts entirely based on capability state.
/// Feels like Apple Books / Photos — no service management visible.
/// Advanced actions (restart, remove, open in browser) are in the toolbar menu.
struct BooksHomeView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let facade: any BooksFacade
    @State private var showingConnectSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                mainContent
            }
            .padding(24)
        }
        .navigationTitle("Books")
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, alignment: .center)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                advancedMenu
            }
        }
        .sheet(isPresented: $showingConnectSheet) {
            if let kavita = facade as? KavitaBooksFacade {
                BooksConnectSheet(facade: kavita)
            }
        }
        .onChange(of: showingConnectSheet) {
            // Refresh after sheet dismissal to pick up new connection state
            if !showingConnectSheet {
                facade.refresh()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
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
                Text("Powered by Kavita")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    statusDot
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch resolvedState {
        case .starting:
            ProgressView()
                .controlSize(.mini)
        case .needsSetup, .settingUp:
            Circle().fill(.orange).frame(width: 8, height: 8)
        case .empty, .ready, .scanning:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .error:
            Circle().fill(.red).frame(width: 8, height: 8)
        case .stopped:
            Circle().fill(.secondary.opacity(0.5)).frame(width: 8, height: 8)
        }
    }

    private var statusLabel: String {
        switch resolvedState {
        case .starting:    "Starting up..."
        case .needsSetup:  "Needs setup"
        case .settingUp:   "Setting up..."
        case .empty:       "Running"
        case .ready:       "Running"
        case .scanning:    "Scanning..."
        case .error:       "Error"
        case .stopped:     "Offline"
        }
    }

    // MARK: - Main Content (State-Driven)

    @ViewBuilder
    private var mainContent: some View {
        switch resolvedState {
        case .stopped:
            stoppedView
        case .starting:
            startingView
        case .needsSetup:
            needsSetupView
        case .settingUp:
            settingUpView
        case .empty:
            emptyView
        case .ready:
            readyView
        case .scanning:
            scanningView
        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - State: Stopped

    private var stoppedView: some View {
        centeredCard {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Your library is offline")
                .font(.headline)
            Text("Start your library to browse and manage your books.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Start Library") {
                Task { try? await facade.perform(.start) }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(serviceManager.isPerformingAction)
        }
    }

    // MARK: - State: Starting

    private var startingView: some View {
        centeredCard {
            ProgressView()
                .controlSize(.regular)
            Text("Starting your library...")
                .font(.headline)
            Text("This usually takes a few seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - State: Needs Setup

    private var needsSetupView: some View {
        centeredCard {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Sign in to your library")
                .font(.headline)
            Text("An existing account was found. Sign in to connect Haven to your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Sign In") {
                showingConnectSheet = true
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }

    // MARK: - State: Setting Up

    private var settingUpView: some View {
        centeredCard {
            ProgressView()
                .controlSize(.regular)
            Text("Setting up your library...")
                .font(.headline)
            Text("Connecting to your book collection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - State: Empty

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            libraryInfoSection

            centeredCard {
                Image(systemName: "books.vertical")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Your library is empty")
                    .font(.headline)
                Text("Add books to your library folder and they'll appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Open Library Folder") {
                        if let lib = facade.library {
                            let path = (lib.libraryPath as NSString).expandingTildeInPath
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    Button("Rescan") {
                        Task { try? await facade.rescan() }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
        }
    }

    // MARK: - State: Ready

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            libraryInfoSection

            // Device access: server address + OPDS feed + QR codes
            if let kavita = facade as? KavitaBooksFacade,
               let address = kavita.serverAddress {
                DeviceAccessSection(
                    serverAddress: address,
                    opdsURL: kavita.opdsURL
                )
            }

            // Show signed-in user for custom accounts (not Haven-managed)
            if let kavita = facade as? KavitaBooksFacade,
               !kavita.isManagedByHaven,
               let username = kavita.connectedUsername {
                HStack {
                    Label("Signed in as \(username)", systemImage: "person.crop.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Sign Out") {
                        kavita.signOut()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - State: Scanning

    private var scanningView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Scanning banner
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scanning your library...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("New books will appear when the scan is complete.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            libraryInfoSection

            // Device access (still show while scanning)
            if let kavita = facade as? KavitaBooksFacade,
               let address = kavita.serverAddress {
                DeviceAccessSection(
                    serverAddress: address,
                    opdsURL: kavita.opdsURL
                )
            }
        }
    }

    // MARK: - State: Error

    private func errorView(message: String) -> some View {
        centeredCard {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("We couldn't load your library")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                if let kavita = facade as? KavitaBooksFacade {
                    if kavita.isManagedByHaven {
                        Button("Retry") {
                            Task { await kavita.autoConnect() }
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)

                        Button("Sign In") {
                            kavita.disconnect()
                            showingConnectSheet = true
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    } else {
                        Button("Sign In") {
                            kavita.disconnect()
                            showingConnectSheet = true
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    }
                }
            }
        }
    }

    // MARK: - Shared Components

    private var libraryInfoSection: some View {
        GroupBox("Library") {
            VStack(spacing: 0) {
                if let lib = facade.library {
                    DetailRow(label: "Location", value: lib.libraryPath)
                    if let count = lib.itemCount {
                        Divider().padding(.vertical, 6)
                        DetailRow(label: "Items", value: "\(count) series")
                    }
                    Divider().padding(.vertical, 6)
                    HStack {
                        Text("Supports EPUB, PDF, CBZ, CBR, and more.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button("Add Books", systemImage: "plus") {
                            let path = (lib.libraryPath as NSString).expandingTildeInPath
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }
            }
            .padding(4)
        }
    }

    /// Reusable centered card for state screens.
    private func centeredCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(spacing: 16) {
                content()
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    // MARK: - Advanced Menu (Toolbar)

    private var advancedMenu: some View {
        Menu {
            if facade.library != nil, facade.setupState == .ready {
                Button("Rescan Library", systemImage: "arrow.triangle.2.circlepath") {
                    Task { try? await facade.rescan() }
                }
            }

            if let lib = facade.library {
                Button("Open Library Folder", systemImage: "folder") {
                    let path = (lib.libraryPath as NSString).expandingTildeInPath
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            }

            Divider()

            Button("Remove Library", systemImage: "trash", role: .destructive) {
                Task { try? await facade.perform(.remove) }
            }

        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - State Resolution

    /// Maps facade state + setup state + library data into a single UI state.
    private var resolvedState: BooksUIState {
        switch facade.state {
        case .idle:
            return .stopped
        case .starting:
            return .starting
        case .error(let msg):
            return .error(msg)
        case .degraded:
            return .error("Library is running with issues")
        case .ready:
            // When managed by Haven and auto-connect is actively working, show settingUp
            if let kavita = facade as? KavitaBooksFacade,
               kavita.isManagedByHaven,
               (kavita.isAutoConnecting || kavita.connectionState == .connecting) {
                return .settingUp
            }
            switch facade.setupState {
            case .needsSetup:
                return .needsSetup
            case .settingUp:
                return .settingUp
            case .failed(let msg):
                return .error(msg)
            case .ready:
                if let lib = facade.library {
                    if lib.scanStatus == .scanning {
                        return .scanning
                    }
                    if let count = lib.itemCount, count > 0 {
                        return .ready
                    }
                    return .empty
                }
                return .empty
            }
        }
    }

    // MARK: - Helpers

    private var service: InstalledService? {
        serviceManager.installedServices.first { $0.id == facade.capabilityID }
    }
}

// MARK: - UI State Enum

private enum BooksUIState {
    case stopped
    case starting
    case needsSetup
    case settingUp
    case empty
    case ready
    case scanning
    case error(String)
}

// MARK: - Detail Row

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
