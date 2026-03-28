/// A named collection of ``Capability`` values that belong together.
///
/// A bundle is the unit of deployment: everything in a bundle is
/// resolved, scheduled, and torn down as a group.
public struct Bundle: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let capabilities: [Capability]

    public init(id: String, name: String, capabilities: [Capability]) {
        self.id = id
        self.name = name
        self.capabilities = capabilities
    }
}
