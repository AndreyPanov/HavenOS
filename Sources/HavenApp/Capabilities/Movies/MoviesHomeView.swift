import AppKit
import SwiftUI
import HavenFacade

/// Native Movies capability screen.
///
/// State-driven UI that adapts based on capability state.
/// Features an inline progressive setup wizard for first-run configuration
/// (instead of a modal ConnectSheet used by Books/Music).
struct MoviesHomeView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let facade: any MoviesFacade
    @State private var showingConnectSheet = false
    @State private var pendingRescanOnFocus = false
    @State private var selectedLibraryPath = "~/Movies"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                mainContent
            }
            .padding(24)
        }
        .navigationTitle("Movies")
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, alignment: .center)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                advancedMenu
            }
        }
        .sheet(isPresented: $showingConnectSheet) {
            ConnectSheet(
                facade: facade,
                icon: "film",
                libraryLabel: "movie library"
            )
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
                systemName: service?.icon ?? "film",
                imagePath: service?.iconImagePath,
                size: 56
            )
            .glassEffect(in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("Movies")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Powered by \(facade.backendName)")
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
        case .starting, .settingUp, .setupWizard:
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
        case .starting:      "Starting up\u{2026}"
        case .needsSetup:    "Needs setup"
        case .settingUp:     "Setting up\u{2026}"
        case .setupWizard:   "Setting up\u{2026}"
        case .empty:         "Ready"
        case .ready:         "Ready"
        case .updating:      "Scanning\u{2026}"
        case .error:         "Error"
        case .stopped:       "Offline"
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
        case .setupWizard(let phase):
            setupWizardView(phase: phase)
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
            Image(systemName: "film")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Your movie library is offline")
                .font(.headline)
            Text("Start your library to browse and stream your movies.")
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
            Text("Starting your movie library\u{2026}")
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
            Text("An existing account was found. Sign in to connect Haven to your movie library.")
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
            Text("Setting up your movie library\u{2026}")
                .font(.headline)
            Text("This usually takes a few seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - State: Setup Wizard (Progressive Inline Form)

    private func setupWizardView(phase: SetupPhase) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setting up your movie library")
                .font(.headline)
            Text("Haven is configuring everything for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                // Step 1: Server ready
                wizardStepCard(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    title: "Server ready",
                    completed: phase != .waitingForServer
                ) {
                    if phase == .waitingForServer {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for server to start\u{2026}")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Step 2: Account created
                if phase != .waitingForServer {
                    wizardStepCard(
                        icon: "checkmark.circle.fill",
                        iconColor: .green,
                        title: "Account created",
                        completed: phase != .creatingAccount
                    ) {
                        if phase == .creatingAccount {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Creating your account\u{2026}")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        } else if phase != .creatingAccount {
                            if let username = facade.connectedUsername {
                                Text("Signed in as \(username)")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Step 3: Choose library folder
                if phase == .awaitingLibraryPath || phase == .creatingLibrary || isScanning(phase) || phase == .complete {
                    wizardStepCard(
                        icon: phase == .awaitingLibraryPath ? "folder.badge.questionmark" : "checkmark.circle.fill",
                        iconColor: phase == .awaitingLibraryPath ? .blue : .green,
                        title: "Where are your movies?",
                        completed: phase != .awaitingLibraryPath
                    ) {
                        if phase == .awaitingLibraryPath {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Choose the folder with your movies and TV shows. Haven will organize and stream everything in it.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text("Tip: Organize TV shows as Show Name/Season 1/episode.mkv for best results. Movies can be loose files or in their own folders.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 8) {
                                    Text(selectedLibraryPath)
                                        .font(.system(.callout, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                                    Button("Choose\u{2026}") {
                                        pickFolder()
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)
                                }

                                Button("Continue") {
                                    Task {
                                        try? await facade.setLibraryPath(selectedLibraryPath, contentType: .moviesAndShows)
                                    }
                                }
                                .buttonStyle(.glassProminent)
                                .controlSize(.regular)
                                .disabled(selectedLibraryPath.isEmpty)
                            }
                        } else {
                            Text(selectedLibraryPath)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Step 4: Scanning
                if isScanning(phase) || phase == .creatingLibrary {
                    wizardStepCard(
                        icon: "magnifyingglass",
                        iconColor: .blue,
                        title: "Finding your movies\u{2026}",
                        completed: false
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            if case .scanning(let progress) = phase, let pct = progress {
                                ProgressView(value: pct / 100)
                                Text("\(Int(pct))% complete")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Downloading metadata and artwork. This may take a while for large libraries.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: wizardPhaseKey(phase))
        }
    }

    private func wizardStepCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        completed: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(completed ? .green : iconColor)
                    .frame(width: 24, alignment: .center)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(completed ? .secondary : .primary)
                    content()
                }
            }
            .padding(4)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose your movies folder"

        let expandedPath = (selectedLibraryPath as NSString).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: expandedPath)

        if panel.runModal() == .OK, let url = panel.url {
            selectedLibraryPath = url.path
        }
    }

    private func isScanning(_ phase: SetupPhase) -> Bool {
        if case .scanning = phase { return true }
        return false
    }

    private func wizardPhaseKey(_ phase: SetupPhase) -> String {
        switch phase {
        case .waitingForServer: "waiting"
        case .creatingAccount: "creating"
        case .awaitingLibraryPath: "path"
        case .awaitingLibraryType: "type"
        case .creatingLibrary: "library"
        case .scanning: "scanning"
        case .complete: "complete"
        }
    }

    // MARK: - State: Empty

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 24) {
            libraryCard

            RestoreFromBackupSection(
                capabilityID: facade.capabilityID,
                libraryPath: facade.library?.libraryPath,
                label: "Movies"
            )

            centeredCard {
                Image(systemName: "film")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Your library is empty")
                    .font(.headline)
                Text("Add movie files to your library folder \u{2014} metadata and artwork will be downloaded automatically.\nSwitch back here and your library will update shortly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Open Movies Folder") {
                    if let lib = facade.library {
                        let path = (lib.libraryPath as NSString).expandingTildeInPath
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
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

            accountInfoSection

            deviceAccessSection
        }
    }

    // MARK: - State: Updating

    private var updatingView: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scanning your movie library\u{2026}")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Downloading metadata and artwork. This may take a while for large libraries.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            libraryCard

            accountInfoSection

            deviceAccessSection
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
                if facade.isManagedByHaven {
                    Button("Retry") {
                        Task { await facade.autoConnect() }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    Button("Sign In") {
                        facade.disconnect()
                        showingConnectSheet = true
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                } else {
                    Button("Sign In") {
                        facade.disconnect()
                        showingConnectSheet = true
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    // MARK: - Library Card

    private var libraryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                if let lib = facade.library {
                    // Stats
                    HStack(spacing: 24) {
                        if let count = lib.movieCount, count > 0 {
                            statView(count: count, label: count == 1 ? "movie" : "movies")
                        }
                        if let count = lib.showCount, count > 0 {
                            statView(count: count, label: count == 1 ? "show" : "shows")
                        }
                    }

                    // Folder paths
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(lib.libraryPaths, id: \.self) { path in
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(path)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                if lib.libraryPaths.count > 1 {
                                    Button {
                                        Task { try? await facade.removeLibraryPath(path) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove this folder")
                                }
                            }
                        }
                    }

                    // Actions
                    HStack(spacing: 8) {
                        Button("Add Folder", systemImage: "plus") {
                            addFolder()
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)

                        Button("Open Folder", systemImage: "folder") {
                            let path = (lib.libraryPath as NSString).expandingTildeInPath
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                            pendingRescanOnFocus = true
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)

                        if facade.setupState == .ready {
                            Button("Check for New Movies", systemImage: "arrow.triangle.2.circlepath") {
                                Task { try? await facade.rescan() }
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }

                        Spacer()
                    }

                    // Hint
                    Text("Add your movie files to the library folders \u{2014} metadata and artwork will be downloaded automatically.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(4)
        }
    }

    private func statView(count: Int, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(count)")
                .font(.system(.title, design: .rounded, weight: .semibold))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder to add to your movie library"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                try? await facade.addLibraryPath(url.path)
            }
        }
    }

    // MARK: - Account Info

    @ViewBuilder
    private var accountInfoSection: some View {
        if let username = facade.connectedUsername {
            AccountInfoSection(username: username)
        }
    }

    // MARK: - Device Access

    @ViewBuilder
    private var deviceAccessSection: some View {
        if let access = facade.deviceAccessInfo {
            MoviesDeviceAccessSection(
                serverAddress: access.serverAddress,
                username: access.username,
                password: access.password
            )
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
                ForEach(lib.libraryPaths, id: \.self) { path in
                    Button("Open \(URL(fileURLWithPath: path).lastPathComponent)", systemImage: "folder") {
                        let expanded = (path as NSString).expandingTildeInPath
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expanded)
                    }
                }
            }

            Button("Add Folder\u{2026}", systemImage: "folder.badge.plus") {
                addFolder()
            }

            if facade.setupState == .ready {
                Button("Refresh Metadata", systemImage: "arrow.triangle.2.circlepath") {
                    Task { try? await facade.rescan() }
                }
            }

            if let url = facade.advancedURL {
                Divider()
                Button("Open in Browser", systemImage: "globe") {
                    NSWorkspace.shared.open(url)
                }
            }

            if !facade.isManagedByHaven, facade.connectedUsername != nil {
                Divider()
                Button("Sign Out", systemImage: "person.crop.circle.badge.minus") {
                    facade.signOut()
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

    private var resolvedState: MoviesUIState {
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
            // Check for active setup wizard
            if let phase = facade.setupPhase {
                return .setupWizard(phase)
            }

            if facade.isManagedByHaven,
               (facade.isAutoConnecting || facade.connectionState == .connecting) {
                return .settingUp
            }
            if facade.isManagedByHaven, facade.autoConnectExhausted {
                return .error("Couldn\u{2019}t connect automatically \u{2014} try signing in manually")
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
                    let hasContent = (lib.movieCount ?? 0) > 0
                        || (lib.showCount ?? 0) > 0
                    if hasContent {
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

private enum MoviesUIState {
    case stopped
    case starting
    case needsSetup
    case settingUp
    case setupWizard(SetupPhase)
    case empty
    case ready
    case updating
    case error(String)
}
