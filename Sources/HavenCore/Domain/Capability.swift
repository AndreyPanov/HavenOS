import Foundation

/// A user-facing feature that Haven can provide.
///
/// Capabilities are the leaf-level building blocks of the system.
/// They are grouped into ``Bundle``s and executed inside
/// ``RuntimeUnit``s.
///
/// Example: "test-library" is a capability — it declares that the
/// system can manage a test library.
public struct Capability: Identifiable, Codable, Hashable, Sendable {
    /// Reverse-DNS style identifier, e.g. `"haven.capability.test-library"`.
    public let id: String

    /// Human-readable display name, e.g. `"Test Library"`.
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
    /// Example: a test library capability.
    public static let testLibraryExample = Capability(
        id: "haven.capability.test-library",
        name: "Test Library",
        version: "1.0.0",
        summary: "Manage a synthetic test library."
    )
}
