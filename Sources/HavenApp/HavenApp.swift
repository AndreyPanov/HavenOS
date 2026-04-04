import AppKit
import SwiftUI

@main
struct HavenApp: App {
    @State private var settings = HavenSettingsModel()
    @State private var serviceManager = ServiceManager()

    init() {
        // Ensure the app runs as a regular GUI application with dock icon and menu bar,
        // even when launched as a bare executable outside a .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(serviceManager)
                .onAppear {
                    serviceManager.load(catalogURL: settings.catalogFolderURL)
                }
        }
        .defaultSize(width: 1100, height: 700)
    }
}
