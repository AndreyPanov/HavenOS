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
    public let description: String?

    /// SF Symbol name for the capability icon (e.g. `"books.vertical"`).
    public let icon: String?

    /// Rich multi-line description for the discovery detail page.
    public let fullDescription: String?

    /// Feature tags displayed as badges (e.g. `["Python", "eBook management"]`).
    public let notes: [String]

    /// Custom icon image filename relative to the service folder.
    /// When present, takes priority over the SF Symbol `icon`.
    public let iconImage: String?

    /// Image filenames relative to the service folder for the discovery page.
    public let screenshots: [String]

    public init(
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        icon: String? = nil,
        fullDescription: String? = nil,
        notes: [String] = [],
        iconImage: String? = nil,
        screenshots: [String] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.icon = icon
        self.fullDescription = fullDescription
        self.notes = notes
        self.iconImage = iconImage
        self.screenshots = screenshots
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        fullDescription = try c.decodeIfPresent(String.self, forKey: .fullDescription)
        notes = try c.decodeIfPresent([String].self, forKey: .notes) ?? []
        iconImage = try c.decodeIfPresent(String.self, forKey: .iconImage)
        screenshots = try c.decodeIfPresent([String].self, forKey: .screenshots) ?? []
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
        description: "Manage a synthetic test library.",
        icon: "books.vertical",
        fullDescription: "A synthetic test library for verifying Haven's spec loading and service lifecycle.",
        notes: ["Lightweight", "Test"]
    )

    /// Returns a copy with resolved image paths (icon image + screenshots).
    public func withResolvedImages(iconImage: String? = nil, screenshots: [String]? = nil) -> Capability {
        Capability(
            id: id, name: name, version: version, description: description,
            icon: icon, fullDescription: fullDescription, notes: notes,
            iconImage: iconImage ?? self.iconImage,
            screenshots: screenshots ?? self.screenshots
        )
    }
}
