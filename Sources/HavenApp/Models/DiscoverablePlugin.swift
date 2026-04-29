import Foundation

struct DiscoverablePlugin: Identifiable, Hashable {
    let id: String
    /// User-facing capability name (e.g. "Books", "Music", "Movies").
    let name: String
    /// Backend product name (e.g. "Kavita", "Navidrome", "Jellyfin").
    let backendName: String
    let summary: String
    let icon: String
    let iconImagePath: String?
    let notes: [String]
    let isInstalled: Bool
    let fullDescription: String
    let screenshotPaths: [String]
}
