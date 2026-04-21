import SwiftUI
import HavenFacade

struct HomeView: View {
    @Environment(ServiceManager.self) private var serviceManager
    @State private var path = NavigationPath()

    private var plugins: [DiscoverablePlugin] {
        serviceManager.discoverablePlugins
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Add capabilities to your Haven")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260, maximum: 360))],
                        spacing: 16
                    ) {
                        ForEach(plugins) { plugin in
                            NavigationLink(value: plugin) {
                                CapabilityCardView(plugin: plugin)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Haven")
            .navigationDestination(for: DiscoverablePlugin.self) { plugin in
                DiscoveryDetailView(plugin: plugin)
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(ServiceManager())
        .frame(width: 800, height: 600)
}
