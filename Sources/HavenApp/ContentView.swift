import SwiftUI

enum SidebarItem: String, Hashable {
    case home
    case discovery
    case settings
}

struct ContentView: View {
    @Environment(ServiceManager.self) private var serviceManager
    @State private var selectedSidebar: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSidebar) {
                Section("Services") {
                    Label("Home", systemImage: "house")
                        .tag(SidebarItem.home)
                    Label("Discovery", systemImage: "square.grid.2x2")
                        .tag(SidebarItem.discovery)
                }
                Section("Preferences") {
                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .navigationTitle("Haven")
        } detail: {
            Group {
                switch selectedSidebar {
                case .home:
                    HomeView()
                case .discovery:
                    DiscoveryView()
                case .settings:
                    SettingsView()
                case nil:
                    Text("Select a section")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .id(selectedSidebar)
        }
        .alert("Error", isPresented: Binding(
            get: { serviceManager.lastError != nil },
            set: { if !$0 { serviceManager.lastError = nil } }
        )) {
            Button("OK") { serviceManager.lastError = nil }
        } message: {
            if let error = serviceManager.lastError {
                Text(error)
            }
        }
        .sheet(item: Binding(
            get: { serviceManager.pendingInstructions },
            set: { serviceManager.pendingInstructions = $0 }
        )) { info in
            PostInstallSheet(info: info)
        }
    }
}

#Preview {
    ContentView()
        .environment(HavenSettingsModel())
        .environment(ServiceManager())
}
