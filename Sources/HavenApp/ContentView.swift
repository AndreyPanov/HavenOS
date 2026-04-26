import SwiftUI
import HavenFacade

enum SidebarItem: Hashable {
    case home
    case capability(String) // capability ID
    case backup
    case settings
}

package struct ContentView: View {
    @Environment(ServiceManager.self) private var serviceManager
    @State private var selectedSidebar: SidebarItem? = .home

    package init() {}

    /// Installed capabilities that have native UI (sidebar tabs).
    private var capabilityTabs: [InstalledService] {
        serviceManager.installedServices.filter {
            serviceManager.hasNativeUI(for: $0.id)
        }
    }

    package var body: some View {
        NavigationSplitView {
            List(selection: $selectedSidebar) {
                Section("Haven") {
                    Label("Home", systemImage: "house")
                        .tag(SidebarItem.home)
                }

                if !capabilityTabs.isEmpty {
                    Section("Capabilities") {
                        ForEach(capabilityTabs) { service in
                            Label(capabilityLabel(for: service), systemImage: service.icon)
                                .tag(SidebarItem.capability(service.id))
                        }
                    }
                }

                Section("Preferences") {
                    Label("Backup", systemImage: "externaldrive")
                        .tag(SidebarItem.backup)
                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
            }
            .animation(.default, value: capabilityTabs.map(\.id))
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            .navigationTitle("Haven")
        } detail: {
            Group {
                switch selectedSidebar {
                case .home:
                    HomeView()
                case .capability(let id):
                    capabilityView(for: id)
                case .backup:
                    BackupView()
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
        .onChange(of: serviceManager.installedServices.map(\.id)) { old, new in
            // Auto-navigate to newly installed capability tab
            let added = Set(new).subtracting(old)
            if let newID = added.first, serviceManager.hasNativeUI(for: newID) {
                withAnimation {
                    selectedSidebar = .capability(newID)
                }
            }
        }
    }

    /// User-facing tab label — capability type, not backend name.
    private func capabilityLabel(for service: InstalledService) -> String {
        serviceManager.userFacingName(for: service)
    }

    @ViewBuilder
    private func capabilityView(for id: String) -> some View {
        if let facade = serviceManager.facade(for: id) as? any BooksFacade {
            BooksHomeView(facade: facade)
        } else if let facade = serviceManager.facade(for: id) as? any MusicFacade {
            MusicHomeView(facade: facade)
        } else if let facade = serviceManager.facade(for: id) as? any MoviesFacade {
            MoviesHomeView(facade: facade)
        } else if serviceManager.facade(for: id) != nil {
            ServiceDetailView(serviceID: id)
        } else {
            Text("Service not found")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ContentView()
        .environment(HavenSettingsModel())
        .environment(ServiceManager())
}
