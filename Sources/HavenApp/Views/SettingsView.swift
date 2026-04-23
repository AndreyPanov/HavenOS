import SwiftUI
import UniformTypeIdentifiers
import HavenCore
import HavenFacade

struct SettingsView: View {
    @Environment(HavenSettingsModel.self) private var settings
    @Environment(ServiceManager.self) private var serviceManager
    @State private var showFolderPicker = false
    @State private var activeSheet: SettingsSheet?

    private enum SettingsSheet: Identifiable {
        case booksConnect
        case musicConnect
        var id: Int { hashValue }
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Catalog") {
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

                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: settings.catalogFolderURL.path)
                    }

                    if settings.catalogFolder != HavenSettingsModel.defaultCatalogFolder {
                        Button("Reset to Default") {
                            settings.catalogFolder = HavenSettingsModel.defaultCatalogFolder
                        }
                    }
                }

                catalogStatusBlock
            }

            Section("General") {
                LabeledContent("Data Directory") {
                    Text(settings.dataDirectory)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                Toggle("Automatically Start Installed Services", isOn: $settings.autoStartServices)
            }

            Section("Paths") {
                LabeledContent("Base Directory") {
                    Text(settings.baseDirectory)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Downloads") {
                    Text(settings.downloadsDirectory)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Installed Artifacts") {
                    Text(settings.artifactsDirectory)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            // Dynamic capability sections
            if let kavitaFacade = kavitaFacade {
                booksLibrarySection(kavitaFacade)
            }

            if let navidromeFacade = navidromeFacade {
                musicLibrarySection(navidromeFacade)
            }

            Section("Advanced") {
                Toggle("Show Internal Details", isOn: $settings.showInternalDetails)
                LabeledContent("Logs") {
                    Button("Open Logs Folder") {
                        // TODO: Open ~/.haven/Services/*/logs in Finder
                    }
                }
                LabeledContent("Service State") {
                    Button("Rebuild Service State") {
                        // TODO: Reconcile persisted state with launchd reality
                    }
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text("\(settings.version) (\(settings.buildNumber))")
                        .foregroundStyle(.secondary)
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
            switch sheet {
            case .booksConnect:
                if let kavita = kavitaFacade {
                    BooksConnectSheet(facade: kavita)
                }
            case .musicConnect:
                if let navidrome = navidromeFacade {
                    MusicConnectSheet(facade: navidrome)
                }
            }
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

    /// Returns the Kavita facade if Books is installed.
    private var kavitaFacade: KavitaBooksFacade? {
        serviceManager.facade(for: "haven.capability.kavita") as? KavitaBooksFacade
    }

    /// Returns the Navidrome facade if Music is installed.
    private var navidromeFacade: NavidromeMusicFacade? {
        serviceManager.facade(for: "haven.capability.navidrome") as? NavidromeMusicFacade
    }

    private func booksLibrarySection(_ facade: KavitaBooksFacade) -> some View {
        Section("Books Library") {
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
                        activeSheet = .booksConnect
                    }
                }
            }
        }
    }

    private func musicLibrarySection(_ facade: NavidromeMusicFacade) -> some View {
        Section("Music Library") {
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
                        activeSheet = .musicConnect
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
        .frame(width: 600, height: 500)
}
