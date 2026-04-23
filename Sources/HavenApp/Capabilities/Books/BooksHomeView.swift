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
    @State private var pendingRescanOnFocus = false

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
            if !showingConnectSheet {
                facade.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if pendingRescanOnFocus {
                pendingRescanOnFocus = false
                Task { try? await facade.rescan() }
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
        case .starting, .settingUp:
            ProgressView()
                .controlSize(.mini)
        case .needsSetup:
            Circle().fill(.orange).frame(width: 8, height: 8)
        case .empty, .ready, .updating:
            Circle().fill(.green).frame(width: 8, height: 8)
        case .error:
            Circle().fill(.red).frame(width: 8, height: 8)
        case .stopped:
            Circle().fill(.secondary.opacity(0.5)).frame(width: 8, height: 8)
        }
    }

    private var statusLabel: String {
        switch resolvedState {
        case .starting:    "Starting up…"
        case .needsSetup:  "Needs setup"
        case .settingUp:   "Setting up…"
        case .empty:       "Ready"
        case .ready:       "Ready"
        case .updating:    "Updating…"
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
        case .updating:
            updatingView
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
            Text("Starting your library…")
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
            Text("Setting up your library…")
                .font(.headline)
            Text("This usually takes a few seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - State: Empty

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 24) {
            libraryCard

            centeredCard {
                Image(systemName: "books.vertical")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Your library is empty")
                    .font(.headline)
                Text("Drop books into your library folder — Haven takes care of the rest.\nSwitch back here and your library will update automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Open Library Folder") {
                    if let lib = facade.library {
                        let path = (lib.libraryPath as NSString).expandingTildeInPath
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                        pendingRescanOnFocus = true
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - State: Ready

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 24) {
            libraryCard

            scanErrorsSection

            accountInfoSection

            if let kavita = facade as? KavitaBooksFacade,
               let address = kavita.serverAddress {
                DeviceAccessSection(
                    serverAddress: address,
                    opdsURL: kavita.opdsURL
                )
            }
        }
    }

    // MARK: - State: Updating

    private var updatingView: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updating your library…")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("New books will appear shortly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            libraryCard

            accountInfoSection

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
            Text("Something went wrong")
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

    // MARK: - Library Card

    private var libraryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                if let lib = facade.library {
                    // Book count (prominent)
                    if let count = lib.itemCount {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(count)")
                                .font(.system(.title, design: .rounded, weight: .semibold))
                            Text(count == 1 ? "book" : "books")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Folder path
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(lib.libraryPath)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if facade is KavitaBooksFacade {
                            Button("Change") {
                                pickLibraryFolder()
                            }
                            .buttonStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(.tint)
                        }
                    }

                    // Actions
                    HStack(spacing: 8) {
                        Button("Add Books", systemImage: "plus") {
                            let path = (lib.libraryPath as NSString).expandingTildeInPath
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                            pendingRescanOnFocus = true
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)

                        if facade.setupState == .ready {
                            Button("Check for New Books", systemImage: "arrow.triangle.2.circlepath") {
                                Task { try? await facade.rescan() }
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }

                        Spacer()
                    }

                    // Hint
                    Text("Add your EPUB, PDF, or CBZ files to the library folder — Haven organizes them automatically.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Scan Errors

    @ViewBuilder
    private var scanErrorsSection: some View {
        if let kavita = facade as? KavitaBooksFacade, !kavita.scanErrors.isEmpty {
            GroupBox {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(kavita.scanErrors, id: \.self) { fileName in
                            HStack(spacing: 6) {
                                Image(systemName: "doc.questionmark")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text(fileName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Make sure your files are in a supported format (EPUB, PDF, CBZ).")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                    .padding(.top, 6)
                } label: {
                    Label(
                        "\(kavita.scanErrors.count) book\(kavita.scanErrors.count == 1 ? "" : "s") couldn't be added",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Account Info

    @ViewBuilder
    private var accountInfoSection: some View {
        if let kavita = facade as? KavitaBooksFacade,
           let username = kavita.connectedUsername {
            GroupBox {
                LabeledContent("Signed in as") {
                    Text(username)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Centered Card

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
            if let lib = facade.library {
                Button("Open Library Folder", systemImage: "folder") {
                    let path = (lib.libraryPath as NSString).expandingTildeInPath
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            }

            if facade.setupState == .ready {
                Button("Check for New Books", systemImage: "arrow.triangle.2.circlepath") {
                    Task { try? await facade.rescan() }
                }
            }

            if let kavita = facade as? KavitaBooksFacade,
               !kavita.isManagedByHaven,
               kavita.connectedUsername != nil {
                Divider()
                Button("Sign Out", systemImage: "person.crop.circle.badge.minus") {
                    kavita.signOut()
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
            if let kavita = facade as? KavitaBooksFacade,
               kavita.isManagedByHaven,
               (kavita.isAutoConnecting || kavita.connectionState == .connecting) {
                return .settingUp
            }
            if let kavita = facade as? KavitaBooksFacade,
               kavita.isManagedByHaven,
               kavita.autoConnectExhausted {
                return .error("Couldn't connect automatically — try signing in manually")
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
                        return .updating
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

    // MARK: - Folder Picker

    private func pickLibraryFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Library Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if let lib = facade.library {
            let expanded = (lib.libraryPath as NSString).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expanded)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path

        guard let kavita = facade as? KavitaBooksFacade else { return }
        Task {
            try? await kavita.changeLibraryFolder(to: path)
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
    case updating
    case error(String)
}
