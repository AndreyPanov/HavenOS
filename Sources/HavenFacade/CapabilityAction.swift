/// A user-triggerable action on a capability.
public struct CapabilityAction: Identifiable, Sendable, Hashable {
    public let id: String
    public let label: String
    public let systemImage: String
    public let role: Role

    public init(id: String, label: String, systemImage: String, role: Role = .secondary) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.role = role
    }

    public enum Role: Sendable, Hashable {
        /// Primary action (e.g. Start, Open).
        case primary
        /// Secondary action (e.g. Restart, Rescan).
        case secondary
        /// Destructive action (e.g. Remove).
        case destructive
    }
}

// MARK: - Standard Actions

extension CapabilityAction {
    public static let start = CapabilityAction(
        id: "start", label: "Start", systemImage: "play.circle", role: .primary
    )
    public static let stop = CapabilityAction(
        id: "stop", label: "Stop", systemImage: "stop.circle", role: .secondary
    )
    public static let restart = CapabilityAction(
        id: "restart", label: "Restart", systemImage: "arrow.clockwise", role: .secondary
    )
    public static let openInBrowser = CapabilityAction(
        id: "openInBrowser", label: "Open in Browser", systemImage: "globe", role: .primary
    )
    public static let remove = CapabilityAction(
        id: "remove", label: "Stop & Remove", systemImage: "trash", role: .destructive
    )
}
