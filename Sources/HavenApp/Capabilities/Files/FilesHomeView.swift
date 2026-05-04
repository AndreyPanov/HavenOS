import AppKit
import SwiftUI
import HavenFacade

struct FilesHomeView: View {
    @Environment(ServiceManager.self) private var serviceManager
    let facade: any FilesFacade

    @State private var activeSheet: ActiveSheet?
    @State private var pendingTrashItem: FilesItem?
    @State private var lastError: String?

    private enum ActiveSheet: Identifiable {
        case newFolder
        case rename(FilesItem)

        var id: String {
            switch self {
            case .newFolder:
                "newFolder"
            case .rename(let item):
                "rename-\(item.id)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                mainContent
            }
            .padding(24)
        }
        .navigationTitle("Files")
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, alignment: .center)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                advancedMenu
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newFolder:
                nameSheet(
                    title: "New Folder",
                    actionTitle: "Create",
                    initialName: ""
                ) { name in
                    try await facade.createFolder(named: name)
                }
            case .rename(let item):
                nameSheet(
                    title: "Rename",
                    actionTitle: "Rename",
                    initialName: item.name
                ) { name in
                    try await facade.rename(item, to: name)
                }
            }
        }
        .confirmationDialog(
            "Move to Trash?",
            isPresented: Binding(
                get: { pendingTrashItem != nil },
                set: { if !$0 { pendingTrashItem = nil } }
            ),
            presenting: pendingTrashItem
        ) { item in
            Button("Move to Trash", role: .destructive) {
                Task {
                    do {
                        try await facade.moveToTrash(item)
                    } catch {
                        lastError = error.localizedDescription
                    }
                    pendingTrashItem = nil
                }
            }
        }
        .task {
            await facade.refreshItems()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            ServiceIconView(
                systemName: service?.icon ?? "folder",
                imagePath: service?.iconImagePath,
                size: 56
            )
            .glassEffect(in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text("Files")
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
        case .starting:
            "Starting up…"
        case .needsSetup:
            "Needs setup"
        case .settingUp, .setupWizard:
            "Setting up…"
        case .empty, .ready:
            "Ready"
        case .updating:
            "Updating…"
        case .error:
            "Error"
        case .stopped:
            "Offline"
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch resolvedState {
        case .stopped:
            stoppedView
        case .starting:
            startingView
        case .needsSetup, .settingUp, .setupWizard:
            settingUpView
        case .empty, .ready, .updating:
            readyView
        case .error(let message):
            errorView(message: message)
        }
    }

    private var stoppedView: some View {
        centeredCard {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Files is offline")
                .font(.headline)
            Text("Start Files to browse and access your selected folder.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Start Files") {
                Task { try? await facade.perform(.start) }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(serviceManager.isPerformingAction)
        }
    }

    private var startingView: some View {
        centeredCard {
            ProgressView()
                .controlSize(.regular)
            Text("Starting Files…")
                .font(.headline)
        }
    }

    private var settingUpView: some View {
        centeredCard {
            ProgressView()
                .controlSize(.regular)
            Text("Preparing file access…")
                .font(.headline)
        }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 24) {
            browserCard

            if let access = facade.deviceAccessInfo {
                FilesDeviceAccessSection(
                    serverAddress: access.serverAddress,
                    username: access.username,
                    password: access.password
                )
            }
        }
    }

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

            Button("Retry") {
                facade.refresh()
                Task { await facade.refreshItems() }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Browser

    private var browserCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                browserToolbar

                if let error = facade.folderState.errorMessage ?? lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                Divider()

                if facade.folderState.items.isEmpty {
                    emptyFolderView
                } else {
                    VStack(spacing: 0) {
                        ForEach(facade.folderState.items) { item in
                            fileRow(item)
                            if item.id != facade.folderState.items.last?.id {
                                Divider()
                                    .padding(.leading, 30)
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    private var browserToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Task { await facade.navigateUp() }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Parent Folder")
                .disabled(!canNavigateUp)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentFolderName)
                        .font(.headline)
                    Text(currentPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer()

                Button {
                    activeSheet = .newFolder
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("New Folder")

                Button {
                    Task { await facade.refreshItems() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Refresh")

                Button {
                    openCurrentFolderInFinder()
                } label: {
                    Image(systemName: "finder")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Open in Finder")
            }

            if facade.roots.count > 1 {
                HStack(spacing: 6) {
                    ForEach(facade.roots) { root in
                        rootSelectionButton(root)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rootSelectionButton(_ root: FilesRoot) -> some View {
        let isSelected = root.id == facade.folderState.root?.id
        if isSelected {
            Button(root.label) {
                Task { await facade.openRoot(root) }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
        } else {
            Button(root.label) {
                Task { await facade.openRoot(root) }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    private var emptyFolderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("This folder is empty")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func fileRow(_ item: FilesItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .folder ? "folder" : "doc")
                .font(.body)
                .foregroundStyle(item.kind == .folder ? .blue : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    if let modified = item.modifiedAt {
                        Text(modified.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let byteCount = item.byteCount {
                        Text(formatBytes(byteCount))
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            Menu {
                if item.kind == .folder {
                    Button("Open", systemImage: "folder") {
                        Task { await facade.openFolder(item) }
                    }
                }

                Button("Reveal in Finder", systemImage: "finder") {
                    NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
                }

                Button("Rename", systemImage: "pencil") {
                    activeSheet = .rename(item)
                }

                Button("Move to Trash", systemImage: "trash", role: .destructive) {
                    pendingTrashItem = item
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .menuStyle(.button)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .onTapGesture(count: 2) {
            if item.kind == .folder {
                Task { await facade.openFolder(item) }
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
            }
        }
    }

    // MARK: - Sheets

    private func nameSheet(
        title: String,
        actionTitle: String,
        initialName: String,
        action: @escaping (String) async throws -> Void
    ) -> some View {
        NameEntrySheet(
            title: title,
            actionTitle: actionTitle,
            initialName: initialName,
            action: action,
            onError: { lastError = $0 }
        )
    }

    // MARK: - Toolbar Menu

    private var advancedMenu: some View {
        Menu {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await facade.refreshItems() }
            }

            Button("Open Folder in Finder", systemImage: "folder") {
                openCurrentFolderInFinder()
            }

            if let url = facade.advancedURL {
                Divider()
                Button("Open in Browser", systemImage: "globe") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button("Remove Files", systemImage: "trash", role: .destructive) {
                Task { try? await facade.perform(.remove) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - State Resolution

    private var resolvedState: CapabilityUIState {
        switch facade.state {
        case .idle:
            .stopped
        case .starting:
            .starting
        case .error(let msg):
            .error(msg)
        case .degraded:
            .error("Files is running with issues")
        case .ready:
            switch facade.setupState {
            case .ready:
                facade.folderState.items.isEmpty ? .empty : .ready
            case .settingUp:
                .settingUp
            case .needsSetup:
                .needsSetup
            case .failed(let msg):
                .error(msg)
            }
        }
    }

    // MARK: - Helpers

    private var service: InstalledService? {
        serviceManager.installedServices.first { $0.id == facade.capabilityID }
    }

    private var currentPath: String {
        facade.folderState.currentPath ?? "No folder selected"
    }

    private var currentFolderName: String {
        guard let path = facade.folderState.currentPath else { return "Files" }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    private var canNavigateUp: Bool {
        guard let root = facade.folderState.root,
              let current = facade.folderState.currentPath else { return false }
        return URL(fileURLWithPath: root.path).standardizedFileURL.path
            != URL(fileURLWithPath: current).standardizedFileURL.path
    }

    private func openCurrentFolderInFinder() {
        guard let path = facade.folderState.currentPath else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct NameEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let actionTitle: String
    let initialName: String
    let action: (String) async throws -> Void
    let onError: (String) -> Void

    @State private var name: String
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(
        title: String,
        actionTitle: String,
        initialName: String,
        action: @escaping (String) async throws -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.initialName = initialName
        self.action = action
        self.onError = onError
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking)
                .onSubmit { submit() }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.glass)

                Spacer()

                Button(actionTitle) {
                    submit()
                }
                .buttonStyle(.glassProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    private func submit() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil

        Task {
            do {
                try await action(name)
                dismiss()
            } catch {
                let message = error.localizedDescription
                errorMessage = message
                onError(message)
            }
            isWorking = false
        }
    }
}
