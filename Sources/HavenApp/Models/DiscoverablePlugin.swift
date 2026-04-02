import Foundation

struct DiscoverablePlugin: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let icon: String
    let notes: [String]
    let isInstalled: Bool
    let fullDescription: String
}
