import Foundation

/// An external helper that a runtime unit needs to function.
///
/// Haven validates presence on the system first. If not found but an
/// ``artifact`` is provided, Haven downloads and installs the dependency
/// into the service's local `bin/` directory automatically — the user
/// never sees brew, apt, or any package manager.
public struct Dependency: Codable, Equatable, Sendable {

    /// The category of dependency.
    public enum Kind: String, Codable, Equatable, Sendable {
        /// A standalone executable (e.g. `ffmpeg`, `imagemagick`).
        case helperBinary
        /// A shared library.
        case library
    }

    /// Unique name (e.g. `"ffmpeg"`).
    public let id: String

    /// What type of dependency this is.
    public let kind: Kind

    /// If `true`, installation fails when the dependency is missing
    /// and no ``artifact`` is available for auto-install.
    /// If `false`, Haven warns but allows installation to proceed.
    public let required: Bool

    /// Absolute-path command to verify presence (exit 0 = found).
    /// Example: `"/opt/homebrew/bin/ffmpeg -version"`.
    public let validateCommand: String?

    /// User-facing explanation of what this dependency enables.
    public let description: String?

    /// Optional artifact for auto-installing this dependency.
    /// When present and the dependency is not found on the system,
    /// Haven downloads and extracts this to the service's `bin/` directory.
    public let artifact: Artifact?

    public init(
        id: String,
        kind: Kind,
        required: Bool = false,
        validateCommand: String? = nil,
        description: String? = nil,
        artifact: Artifact? = nil
    ) {
        self.id = id
        self.kind = kind
        self.required = required
        self.validateCommand = validateCommand
        self.description = description
        self.artifact = artifact
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
        validateCommand = try c.decodeIfPresent(String.self, forKey: .validateCommand)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        artifact = try c.decodeIfPresent(Artifact.self, forKey: .artifact)
    }

    /// Validates that the dependency is well-formed.
    public func validate() throws {
        if id.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Dependency id must not be empty.")
        }
    }
}
