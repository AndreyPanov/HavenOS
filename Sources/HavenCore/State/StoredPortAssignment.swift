import Foundation

/// A persisted port assignment for a runtime unit.
public struct StoredPortAssignment: Codable, Equatable, Sendable {
    /// The runtime unit ID this port belongs to.
    public let unitID: String

    /// The assigned port number.
    public let port: Int

    public init(unitID: String, port: Int) {
        self.unitID = unitID
        self.port = port
    }
}
