import Foundation
import HavenCore

/// Preview-only mock data. The real app uses ServiceManager.
enum MockData {
    static let installedServices: [InstalledService] = [
        InstalledService(
            id: "haven.capability.hello-service",
            name: "Hello Service",
            serviceDescription: "A simple greeting service for testing and verifying your Haven setup.",
            icon: "hand.wave",
            iconImagePath: nil,
            status: .running,
            port: 8080,
            dataPath: "~/.haven/Services/haven.capability.hello-service/data",
            instructions: nil,
            onboarding: nil
        ),
        InstalledService(
            id: "haven.capability.calibre-web",
            name: "Calibre-Web",
            serviceDescription: "A web-based e-book library manager powered by Calibre.",
            icon: "books.vertical",
            iconImagePath: nil,
            status: .running,
            port: 8083,
            dataPath: "~/.haven/Services/haven.capability.calibre-web/data",
            instructions: nil,
            onboarding: Onboarding(steps: [
                OnboardingStep(
                    type: .credentials,
                    title: "Default Credentials",
                    body: "Log in with the default admin account. Change the password after first login.",
                    fields: [
                        OnboardingField(label: "Username", value: "admin"),
                        OnboardingField(label: "Password", value: "admin123"),
                    ]
                ),
                OnboardingStep(
                    type: .action,
                    title: "Open Calibre-Web",
                    body: "Access your library in the browser.",
                    url: "http://localhost:8083"
                ),
                OnboardingStep(
                    type: .info,
                    title: "Configure Library Path",
                    body: "On first login, set the Calibre database location to: ~/.haven/Services/calibre-web/data"
                ),
            ])
        ),
    ]

    static let discoverablePlugins: [DiscoverablePlugin] = [
        DiscoverablePlugin(
            id: "haven.capability.kavita",
            name: "Books",
            backendName: "Kavita",
            summary: "Your personal library for books, comics, and manga.",
            icon: "books.vertical",
            iconImagePath: nil,
            notes: ["Books", "Comics", "Manga"],
            isInstalled: false,
            fullDescription: "Your personal library for books, comics, and manga.",
            screenshotPaths: []
        ),
    ]
}
