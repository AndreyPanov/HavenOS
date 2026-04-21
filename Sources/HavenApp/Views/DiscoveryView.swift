import SwiftUI
import HavenCore

struct DiscoveryView: View {
    @Environment(ServiceManager.self) private var serviceManager
    @Environment(HavenSettingsModel.self) private var settings
    @State private var searchText = ""
    @State private var path = NavigationPath()

    private var plugins: [DiscoverablePlugin] {
        serviceManager.discoverablePlugins
    }

    private var filteredPlugins: [DiscoverablePlugin] {
        if searchText.isEmpty { return plugins }
        return plugins.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if plugins.isEmpty {
                    catalogUnavailableView
                } else if filteredPlugins.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    pluginGridView
                }
            }
            .navigationTitle("Discovery")
            .searchable(text: $searchText, prompt: "Search services")
            .navigationDestination(for: DiscoverablePlugin.self) { plugin in
                DiscoveryDetailView(plugin: plugin)
            }
        }
    }

    private var pluginGridView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Find services to add to Haven")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240, maximum: 340))],
                    spacing: 16
                ) {
                    ForEach(filteredPlugins) { plugin in
                        NavigationLink(value: plugin) {
                            CapabilityCardView(plugin: plugin)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var catalogUnavailableView: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                switch serviceManager.catalogState {
                case .folderNotFound(let path):
                    emptyStateHeader(
                        icon: "folder.badge.questionmark",
                        title: "Catalog Folder Not Found",
                        message: "Haven could not find the catalog folder at:\n\(path)"
                    )

                    Button("Open Settings") {
                        // TODO: Navigate to Settings tab
                    }

                case .issues(let issues):
                    emptyStateHeader(
                        icon: "exclamationmark.triangle",
                        title: "Could Not Load Catalog",
                        message: "Haven found \(issues.count) issue\(issues.count == 1 ? "" : "s") while loading specs from the catalog folder."
                    )

                    DisclosureGroup("Show Details") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                                Text(issue.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: 480)

                default:
                    emptyStateHeader(
                        icon: "shippingbox",
                        title: "No Services Available",
                        message: "Your catalog folder is empty. Add service spec files to discover and install services."
                    )
                }

                folderStructureGuide

                HStack(spacing: 12) {
                    Button("Open Catalog Folder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: settings.catalogFolderURL.path)
                    }

                    Button("Reload") {
                        serviceManager.reloadCatalog(from: settings.catalogFolderURL)
                    }
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }

    private func emptyStateHeader(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    private var folderStructureGuide: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Expected Folder Structure", systemImage: "folder")
                    .font(.headline)

                Text("""
                Each service is a subfolder of your catalog folder \
                containing its spec files:
                """)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    structureLine("my-service/", description: "A service folder")
                    specFileLine("capability.json", description: "What the service provides")
                    specFileLine("bundle.json", description: "Which implementation to use")
                    specFileLine("runtimes.json", description: "How to run it (array of units)")
                }
                .padding(.leading, 4)

                Text("""
                The RuntimeUnit `installSource` field can be a \
                path relative to the service folder \
                (e.g. `Artifacts/MyService`).
                """)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
        .frame(maxWidth: 480)
    }

    private func structureLine(_ folder: String, description: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(folder)
                .font(.system(.callout, design: .monospaced))
                .fontWeight(.medium)
            Text("  \u{2014}  \(description)")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private func specFileLine(_ filename: String, description: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(filename)
                .font(.system(.caption, design: .monospaced))
            Text("  \u{2014}  \(description)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 24)
    }
}

#Preview {
    DiscoveryView()
        .environment(ServiceManager())
        .environment(HavenSettingsModel())
        .frame(width: 800, height: 600)
}
