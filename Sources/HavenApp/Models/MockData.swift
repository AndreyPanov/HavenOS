import Foundation

/// Preview-only mock data. The real app uses ServiceManager.
enum MockData {
    static let installedServices: [InstalledService] = [
        InstalledService(
            id: "haven.capability.hello-service",
            name: "Hello Service",
            serviceDescription: "A simple greeting service for testing and verifying your Haven setup.",
            icon: "hand.wave",
            status: .running,
            port: 8080,
            dataPath: "~/.haven/Services/haven.capability.hello-service/data"
        ),
    ]

    static let discoverablePlugins: [DiscoverablePlugin] = [
        DiscoverablePlugin(
            id: "haven.capability.hello-service",
            name: "Hello Service",
            summary: "A simple greeting service for testing Haven.",
            icon: "hand.wave",
            category: .utilities,
            notes: ["Lightweight", "Native service"],
            isInstalled: false,
            fullDescription: "Hello Service is a minimal service that responds to HTTP requests with a greeting. Useful for testing your Haven setup and verifying connectivity."
        ),
    ]
}
