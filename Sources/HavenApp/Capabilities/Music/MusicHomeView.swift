import AppKit
import SwiftUI
import HavenFacade

/// Native Music capability screen.
///
/// State-driven UI that adapts based on capability state.
/// Follows the same pattern as BooksHomeView.
struct MusicHomeView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let facade: any MusicFacade
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
        .navigationTitle("Music")
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, alignment: .center)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                advancedMenu
            }
        }
        .sheet(isPresented: $showingConnectSheet) {
            if let navidrome = facade as? NavidromeMusicFacade {
                MusicConnectSheet(facade: navidrome)
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
                systemName: service?.icon ?? "music.note.house",
                imagePath: service?.iconImagePath,
                size: 56
            )
            .glassEffect(in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("Music")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Powered by Navidrome")
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
        case .updating:    "Scanning…"
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
            Image(systemName: "music.note.house")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Your music library is offline")
                .font(.headline)
            Text("Start your library to browse and stream your music.")
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
            Text("Starting your music library…")
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
            Text("An existing account was found. Sign in to connect Haven to your music library.")
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
            Text("Setting up your music library…")
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
                Image(systemName: "music.note.house")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("Your library is empty")
                    .font(.headline)
                Text("Add music files to your library folder — Navidrome indexes them automatically.\nSwitch back here and your library will update shortly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Open Music Folder") {
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

            if let navidrome = facade as? NavidromeMusicFacade,
               let address = navidrome.serverAddress {
                MusicDeviceAccessSection(serverAddress: address)
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
                    Text("Scanning your music library…")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("New music will appear shortly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            libraryCard

            if let navidrome = facade as? NavidromeMusicFacade,
               let address = navidrome.serverAddress {
                MusicDeviceAccessSection(serverAddress: address)
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
                if let navidrome = facade as? NavidromeMusicFacade {
                    if navidrome.isManagedByHaven {
                        Button("Retry") {
                            Task { await navidrome.autoConnect() }
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)

                        Button("Sign In") {
                            navidrome.disconnect()
                            showingConnectSheet = true
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    } else {
                        Button("Sign In") {
                            navidrome.disconnect()
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
                    // Stats
                    HStack(spacing: 24) {
                        if let count = lib.artistCount, count > 0 {
                            statView(count: count, label: count == 1 ? "artist" : "artists")
                        }
                        if let count = lib.albumCount, count > 0 {
                            statView(count: count, label: count == 1 ? "album" : "albums")
                        }
                        if let count = lib.trackCount, count > 0 {
                            statView(count: count, label: count == 1 ? "track" : "tracks")
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

                        if facade is NavidromeMusicFacade {
                            Button("Change") {
                                pickMusicFolder()
                            }
                            .buttonStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(.tint)
                        }
                    }

                    // Actions
                    HStack(spacing: 8) {
                        Button("Add Music", systemImage: "plus") {
                            let path = (lib.libraryPath as NSString).expandingTildeInPath
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)

                        if facade.setupState == .ready {
                            Button("Check for New Music", systemImage: "arrow.triangle.2.circlepath") {
                                Task { try? await facade.rescan() }
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }

                        Spacer()
                    }

                    // Hint
                    Text("Add your music files to the library folder — Navidrome indexes them automatically.")
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
                Button("Open Music Folder", systemImage: "folder") {
                    let path = (lib.libraryPath as NSString).expandingTildeInPath
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            }

            if facade.setupState == .ready {
                Button("Check for New Music", systemImage: "arrow.triangle.2.circlepath") {
                    Task { try? await facade.rescan() }
                }
            }

            if let navidrome = facade as? NavidromeMusicFacade,
               !navidrome.isManagedByHaven,
               navidrome.connectedUsername != nil {
                Divider()
                Button("Sign Out", systemImage: "person.crop.circle.badge.minus") {
                    navidrome.signOut()
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

    private var resolvedState: MusicUIState {
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
            if let navidrome = facade as? NavidromeMusicFacade,
               navidrome.isManagedByHaven,
               (navidrome.isAutoConnecting || navidrome.connectionState == .connecting) {
                return .settingUp
            }
            if let navidrome = facade as? NavidromeMusicFacade,
               navidrome.isManagedByHaven,
               navidrome.autoConnectExhausted {
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
                    let hasContent = (lib.artistCount ?? 0) > 0
                        || (lib.albumCount ?? 0) > 0
                        || (lib.trackCount ?? 0) > 0
                    if hasContent {
                        return .ready
                    }
                    return .empty
                }
                return .empty
            }
        }
    }

    // MARK: - Folder Picker

    private func pickMusicFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Music Folder"
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

        guard let navidrome = facade as? NavidromeMusicFacade else { return }
        Task {
            try? await navidrome.changeMusicFolder(to: path)
        }
    }

    // MARK: - Helpers

    private var service: InstalledService? {
        serviceManager.installedServices.first { $0.id == facade.capabilityID }
    }
}

// MARK: - UI State Enum

private enum MusicUIState {
    case stopped
    case starting
    case needsSetup
    case settingUp
    case empty
    case ready
    case updating
    case error(String)
}
