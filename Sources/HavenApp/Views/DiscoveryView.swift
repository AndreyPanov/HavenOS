import SwiftUI

struct DiscoveryView: View {
    @Environment(ServiceManager.self) private var serviceManager
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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Find services to add to Haven")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    // Plugin grid
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240, maximum: 340))],
                        spacing: 16
                    ) {
                        ForEach(filteredPlugins) { plugin in
                            NavigationLink(value: plugin) {
                                DiscoveryCardView(plugin: plugin)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Discovery")
            .searchable(text: $searchText, prompt: "Search services")
            .navigationDestination(for: DiscoverablePlugin.self) { plugin in
                DiscoveryDetailView(plugin: plugin)
            }
        }
    }
}

#Preview {
    DiscoveryView()
        .environment(ServiceManager())
        .frame(width: 800, height: 600)
}
