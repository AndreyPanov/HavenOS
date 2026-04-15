import Foundation

/// A single atomic installation action executed after artifact resolution.
///
/// Steps run in order. Each action is deterministic and reversible —
/// on failure, the installer rolls back all completed steps in reverse order.
public struct InstallStep: Codable, Equatable, Sendable {

    /// The operation to perform.
    public enum Action: String, Codable, Equatable, Sendable {
        /// Create a directory (recursive).
        case mkdir
        /// Copy a file or directory.
        case copy
        /// Move a file or directory.
        case move
        /// Set Unix permissions.
        case chmod
        /// Write string content to a file.
        case writeFile
        /// Create a symbolic link.
        case symlink
        /// Generate a cryptographic random secret and inject it as a template variable.
        /// `path` is the variable name (e.g. `"api_key"`), `mode` is the encoding
        /// (`"hex"` or `"base64"`), `content` is the byte length as a string (e.g. `"32"`).
        case generateSecret
        /// Remove a file or empty directory created during install.
        /// Used for post-install cleanup (e.g. removing downloaded archives).
        case cleanup
    }

    /// Which operation to perform.
    public let action: Action

    /// Target path. Supports `${var}` template expansion.
    /// For `generateSecret`, this is the template variable name to inject.
    public let path: String

    /// Source path for `copy`, `move`, and `symlink` actions.
    public let source: String?

    /// Unix permissions string for `chmod` (e.g. `"755"`).
    /// For `generateSecret`, the encoding: `"hex"` (default) or `"base64"`.
    public let mode: String?

    /// File contents for `writeFile`. Supports `${var}` template expansion.
    /// For `generateSecret`, the byte length as a string (e.g. `"32"`).
    public let content: String?

    public init(
        action: Action,
        path: String,
        source: String? = nil,
        mode: String? = nil,
        content: String? = nil
    ) {
        self.action = action
        self.path = path
        self.source = source
        self.mode = mode
        self.content = content
    }

    /// Validates that required fields are present for the given action.
    public func validate() throws {
        if path.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("InstallStep path must not be empty.")
        }
        switch action {
        case .copy, .move, .symlink:
            if source == nil || source!.trimmingCharacters(in: .whitespaces).isEmpty {
                throw ValidationError("InstallStep '\(action.rawValue)' requires a non-empty source.")
            }
        case .chmod:
            if mode == nil || mode!.trimmingCharacters(in: .whitespaces).isEmpty {
                throw ValidationError("InstallStep 'chmod' requires a non-empty mode.")
            }
        case .writeFile:
            if content == nil {
                throw ValidationError("InstallStep 'writeFile' requires content.")
            }
        case .generateSecret:
            if let length = content.flatMap({ Int($0) }), length <= 0 {
                throw ValidationError("InstallStep 'generateSecret' requires a positive byte length.")
            }
        case .mkdir, .cleanup:
            break
        }
    }
}

/// Container for the install block in a RuntimeUnit spec.
public struct InstallBlock: Codable, Equatable, Sendable {
    /// Ordered list of installation steps.
    public let steps: [InstallStep]

    public init(steps: [InstallStep]) {
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps = try c.decodeIfPresent([InstallStep].self, forKey: .steps) ?? []
    }

    /// Validates all steps.
    public func validate() throws {
        for step in steps {
            try step.validate()
        }
    }
}
