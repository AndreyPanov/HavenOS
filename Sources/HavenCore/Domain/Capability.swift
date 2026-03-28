import Foundation

/// A user-facing feature that Haven can provide.
///
/// Capabilities are the leaf-level building blocks of the system.
/// They are grouped into ``Bundle``s and executed inside
/// ``RuntimeUnit``s.
///
/// Example: "music" is a capability — it declares that the system
/// can stream and manage a music library.
public struct Capability: Identifiable, Codable, Hashable, Sendable {
    /// Reverse-DNS style identifier, e.g. `"haven.capability.music"`.
    public let id: String

    /// Human-readable display name, e.g. `"Music"`.
    public let name: String

    /// Semantic version string, e.g. `"1.0.0"`.
    public let version: String

    /// Optional one-line description of what this capability provides.
    public let summary: String?

    public init(
        id: String,
        name: String,
        version: String,
        summary: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.summary = summary
    }

    /// Validates that required fields are non-empty.
    public func validate() throws {
        if id.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Capability id must not be empty.")
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Capability name must not be empty.")
        }
        if version.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Capability version must not be empty.")
        }
    }
}

// MARK: - Example

extension Capability {
    /// Example: a music streaming capability.
    public static let musicExample = Capability(
        id: "haven.capability.music",
        name: "Music",
        version: "1.0.0",
        summary: "Stream and manage a personal music library."
    )
}
