import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HavenCore
import HavenFacade

struct SettingsView: View {
    @Environment(HavenSettingsModel.self) private var settings
    @Environment(ServiceManager.self) private var serviceManager
    @Environment(AppUpdateModel.self) private var appUpdateModel
    @State private var showFolderPicker = false
    @State private var activeSheet: SettingsSheet?

    private struct SettingsSheet: Identifiable {
        let id: String
        let facade: any ConnectableFacade
        let icon: String
        let libraryLabel: String
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("General") {
                LabeledContent("Data Directory") {
                    Text(settings.dataDirectory)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            // Dynamic capability sections
            if let booksFacade = booksFacade {
                capabilityLibrarySection(
                    title: "Books Library",
                    facade: booksFacade,
                    icon: "books.vertical",
                    libraryLabel: "book library"
                )
            }

            if let musicFacade = musicFacade {
                capabilityLibrarySection(
                    title: "Music Library",
                    facade: musicFacade,
                    icon: "music.note.house",
                    libraryLabel: "music library"
                )
            }

            if let moviesFacade = moviesFacade {
                capabilityLibrarySection(
                    title: "Movies Library",
                    facade: moviesFacade,
                    icon: "film",
                    libraryLabel: "movie library"
                )
            }

            if let filesFacade = filesFacade {
                capabilityLibrarySection(
                    title: "Files Access",
                    facade: filesFacade,
                    icon: "folder",
                    libraryLabel: "file access"
                )
            }

            Section("Advanced") {
                // Catalog
                LabeledContent("Catalog Folder") {
                    HStack(spacing: 8) {
                        Text(settings.catalogFolder)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Choose\u{2026}") {
                            showFolderPicker = true
                        }
                        .controlSize(.small)
                    }
                }

                HStack(spacing: 12) {
                    Button("Reload Catalog") {
                        serviceManager.reloadCatalog(from: settings.catalogFolderURL)
                    }

                    Button("Open Catalog in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: settings.catalogFolderURL.path)
                    }

                    if settings.catalogFolder != HavenSettingsModel.defaultCatalogFolder {
                        Button("Reset to Default") {
                            settings.catalogFolder = HavenSettingsModel.defaultCatalogFolder
                        }
                    }
                }

                catalogStatusBlock

                // Logs
                LabeledContent("Logs") {
                    Button("Open Logs Folder") {
                        let logsPath = (settings.baseDirectory as NSString)
                            .expandingTildeInPath + "/Services"
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logsPath)
                    }
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text("\(settings.version) (\(settings.buildNumber))")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Updates") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Button {
                            appUpdateModel.checkForUpdates()
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.down.circle")
                        }
                        .disabled(!appUpdateModel.canCheckForUpdates)

                        if let message = appUpdateModel.configurationMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                Text("Haven is a local service manager for macOS. It installs and manages self-hosted services on your Mac.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .sheet(item: $activeSheet) { sheet in
            ConnectSheet(facade: sheet.facade, icon: sheet.icon, libraryLabel: sheet.libraryLabel)
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                settings.catalogFolder = url.path
            }
        }
    }

    /// Returns the Books facade if installed.
    private var booksFacade: (any BooksFacade)? {
        serviceManager.facade(for: "haven.capability.kavita") as? any BooksFacade
    }

    /// Returns the Music facade if installed.
    private var musicFacade: (any MusicFacade)? {
        serviceManager.facade(for: "haven.capability.navidrome") as? any MusicFacade
    }

    /// Returns the Movies facade if installed.
    private var moviesFacade: (any MoviesFacade)? {
        serviceManager.facade(for: "haven.capability.jellyfin") as? any MoviesFacade
    }

    /// Returns the Files facade if installed.
    private var filesFacade: (any FilesFacade)? {
        serviceManager.facade(for: "haven.capability.filebrowser") as? any FilesFacade
    }

    private func capabilityLibrarySection(
        title: String,
        facade: any ConnectableFacade,
        icon: String,
        libraryLabel: String
    ) -> some View {
        Section(title) {
            Toggle("Account managed by Haven", isOn: Binding(
                get: { facade.isManagedByHaven },
                set: { newValue in
                    if newValue {
                        facade.switchToManaged()
                    } else {
                        facade.switchToCustom()
                    }
                }
            ))

            if !facade.isManagedByHaven {
                if facade.connectionState == .connected, let username = facade.connectedUsername {
                    LabeledContent("Signed in as") {
                        Text(username)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Sign In") {
                        activeSheet = SettingsSheet(
                            id: facade.capabilityID,
                            facade: facade,
                            icon: icon,
                            libraryLabel: libraryLabel
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var catalogStatusBlock: some View {
        switch serviceManager.catalogState {
        case .notLoaded:
            Label("Catalog not loaded yet", systemImage: "circle.dashed")
                .font(.callout)
                .foregroundStyle(.tertiary)

        case .loaded(let counts):
            catalogCountsView(counts: counts, warnings: [])

        case .loadedWithWarnings(let counts, let warnings):
            catalogCountsView(counts: counts, warnings: warnings)

        case .folderNotFound(let path):
            Label {
                Text("Folder not found at: \(path)")
            } icon: {
                Image(systemName: "folder.badge.questionmark")
            }
            .font(.callout)
            .foregroundStyle(.orange)

        case .issues(let issues):
            VStack(alignment: .leading, spacing: 6) {
                Label("\(issues.count) issue\(issues.count == 1 ? "" : "s") loading catalog",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)

                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            Text(issue.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func catalogCountsView(counts: CatalogCounts, warnings: [SpecLoadIssue]) -> some View {
        if counts.capabilities == 0 {
            Label {
                Text("Catalog folder is empty. Add spec files to get started.")
            } icon: {
                Image(systemName: "tray")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if warnings.isEmpty {
                    Label("Catalog loaded", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Label("Catalog loaded with \(warnings.count) warning\(warnings.count == 1 ? "" : "s")",
                          systemImage: "checkmark.circle.trianglebadge.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.yellow)
                }

                HStack(spacing: 16) {
                    countBadge(counts.capabilities, label: "capabilities")
                    countBadge(counts.bundles, label: "bundles")
                    countBadge(counts.runtimeUnits, label: "runtime units")
                }

                if !warnings.isEmpty {
                    DisclosureGroup("Warnings") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(warnings.enumerated()), id: \.offset) { _, issue in
                                Text(issue.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func countBadge(_ count: Int, label: String) -> some View {
        Text("\(count) \(label)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    SettingsView()
        .environment(HavenSettingsModel())
        .environment(ServiceManager())
        .environment(AppUpdateModel())
        .frame(width: 600, height: 500)
}
