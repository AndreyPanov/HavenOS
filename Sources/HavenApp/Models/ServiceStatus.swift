import SwiftUI

enum ServiceStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case running = "Running"
    case stopped = "Stopped"
    case failed = "Failed"
    case installing = "Installing"

    var color: Color {
        switch self {
        case .running: .green
        case .stopped: .secondary
        case .failed: .red
        case .installing: .orange
        }
    }

    var systemImage: String {
        switch self {
        case .running: "circle.fill"
        case .stopped: "circle"
        case .failed: "exclamationmark.circle.fill"
        case .installing: "arrow.down.circle"
        }
    }
}
