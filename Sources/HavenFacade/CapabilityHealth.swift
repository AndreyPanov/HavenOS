/// Health status of a capability, independent of any backend.
public struct CapabilityHealth: Sendable, Equatable {
    public let status: Status
    public let message: String?

    public init(status: Status, message: String? = nil) {
        self.status = status
        self.message = message
    }

    public enum Status: Sendable, Equatable {
        case healthy
        case unhealthy
        case unknown
    }

    public static let unknown = CapabilityHealth(status: .unknown)
    public static let healthy = CapabilityHealth(status: .healthy)
}
