/// A discrete unit of functionality that Haven can provide or require.
///
/// Capabilities are the leaf-level building blocks of the system.
/// They are grouped into ``Bundle``s and executed inside
/// ``RuntimeUnit``s.
public struct Capability: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let version: String

    public init(id: String, name: String, version: String) {
        self.id = id
        self.name = name
        self.version = version
    }
}
