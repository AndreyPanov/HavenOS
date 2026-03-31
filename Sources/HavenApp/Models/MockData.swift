import Foundation

enum MockData {
    static let installedServices: [InstalledService] = [
        InstalledService(
            id: "hello-service",
            name: "Hello Service",
            serviceDescription: "A simple greeting service for testing and verifying your Haven setup.",
            icon: "hand.wave",
            status: .running,
            port: 8080,
            dataPath: "~/.haven/services/hello-service"
        ),
        InstalledService(
            id: "photos",
            name: "Photos",
            serviceDescription: "Self-hosted photo library with automatic organization and sharing.",
            icon: "photo.on.rectangle.angled",
            status: .running,
            port: 2342,
            dataPath: "~/.haven/services/photos"
        ),
        InstalledService(
            id: "music",
            name: "Music",
            serviceDescription: "Personal music streaming and library management.",
            icon: "music.note",
            status: .stopped,
            port: 4533,
            dataPath: "~/.haven/services/music"
        ),
        InstalledService(
            id: "files",
            name: "Files",
            serviceDescription: "File synchronization and sharing across your devices.",
            icon: "folder.fill",
            status: .failed,
            port: 8443,
            dataPath: "~/.haven/services/files"
        ),
    ]

    static let discoverablePlugins: [DiscoverablePlugin] = [
        DiscoverablePlugin(
            id: "hello-service",
            name: "Hello Service",
            summary: "A simple greeting service for testing Haven.",
            icon: "hand.wave",
            category: .utilities,
            notes: ["Lightweight", "Native service"],
            isInstalled: true,
            fullDescription: "Hello Service is a minimal service that responds to HTTP requests with a greeting. Useful for testing your Haven setup and verifying connectivity."
        ),
        DiscoverablePlugin(
            id: "photos",
            name: "Photos",
            summary: "Self-hosted photo library and gallery.",
            icon: "photo.on.rectangle.angled",
            category: .media,
            notes: ["Runs locally", "Auto-organize"],
            isInstalled: true,
            fullDescription: "Photos provides a private, self-hosted photo library with automatic organization, face detection, and sharing capabilities. All your photos stay on your Mac."
        ),
        DiscoverablePlugin(
            id: "music",
            name: "Music",
            summary: "Personal music streaming server.",
            icon: "music.note",
            category: .media,
            notes: ["Runs locally", "Lightweight"],
            isInstalled: true,
            fullDescription: "Music turns your local music collection into a personal streaming service. Access your library from any device on your network."
        ),
        DiscoverablePlugin(
            id: "files",
            name: "Files",
            summary: "File sync and sharing service.",
            icon: "folder.fill",
            category: .files,
            notes: ["Native service", "End-to-end sync"],
            isInstalled: true,
            fullDescription: "Files provides real-time file synchronization across all your devices. Share folders, collaborate on documents, and keep everything in sync."
        ),
        DiscoverablePlugin(
            id: "dns-resolver",
            name: "DNS Resolver",
            summary: "Local DNS resolver for private name resolution.",
            icon: "globe",
            category: .network,
            notes: ["Lightweight", "Network service"],
            isInstalled: false,
            fullDescription: "DNS Resolver provides local DNS resolution for your Haven services. Access services by friendly names instead of port numbers."
        ),
        DiscoverablePlugin(
            id: "notes",
            name: "Notes",
            summary: "Self-hosted note-taking and knowledge base.",
            icon: "note.text",
            category: .utilities,
            notes: ["Runs locally", "Markdown support"],
            isInstalled: false,
            fullDescription: "Notes gives you a private, self-hosted space for note-taking and knowledge management. Supports Markdown, full-text search, and tagging."
        ),
        DiscoverablePlugin(
            id: "library",
            name: "Library",
            summary: "Personal e-book and document manager.",
            icon: "books.vertical",
            category: .media,
            notes: ["Native service", "EPUB support"],
            isInstalled: false,
            fullDescription: "Library manages your personal collection of e-books and documents. Browse, read, and organize your digital library from any device on your network."
        ),
    ]
}
