import Foundation

enum PluginCategory: String, CaseIterable, Identifiable, Hashable {
    case all = "All"
    case media = "Media"
    case files = "Files"
    case network = "Network"
    case utilities = "Utilities"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .media: "play.rectangle"
        case .files: "folder"
        case .network: "network"
        case .utilities: "wrench.and.screwdriver"
        }
    }
}

struct DiscoverablePlugin: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let icon: String
    let category: PluginCategory
    let notes: [String]
    let isInstalled: Bool
    let fullDescription: String
}
