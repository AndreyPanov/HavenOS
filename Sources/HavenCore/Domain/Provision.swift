import Foundation

/// A file to provision during installation.
///
/// Provisions describe files that should be downloaded and placed in the
/// service directory during install. Each provision can be conditional
/// on a boolean setting value.
public struct Provision: Codable, Equatable, Hashable, Sendable {
    /// Human-readable description of what this provision does.
    public let description: String

    /// URL to download from. May contain `${variable}` placeholders before resolution.
    public let source: String

    /// Destination path. May contain `${variable}` placeholders (e.g., `${data_dir}/metadata.db`).
    /// After resolution, must resolve to a path inside the service directory.
    public let destination: String

    /// Setting key that must be `"true"` for this provision to execute.
    /// If nil, the provision always runs.
    public let condition: String?

    public init(
        description: String,
        source: String,
        destination: String,
        condition: String? = nil
    ) {
        self.description = description
        self.source = source
        self.destination = destination
        self.condition = condition
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        description = try c.decode(String.self, forKey: .description)
        source = try c.decode(String.self, forKey: .source)
        destination = try c.decode(String.self, forKey: .destination)
        condition = try c.decodeIfPresent(String.self, forKey: .condition)
    }

    /// Validates that the provision is well-formed.
    public func validate() throws {
        if source.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Provision source must not be empty.")
        }
        if destination.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Provision destination must not be empty.")
        }
    }
}
