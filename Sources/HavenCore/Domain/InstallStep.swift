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
    }

    /// Which operation to perform.
    public let action: Action

    /// Target path. Supports `${var}` template expansion.
    public let path: String

    /// Source path for `copy`, `move`, and `symlink` actions.
    public let source: String?

    /// Unix permissions string for `chmod` (e.g. `"755"`).
    public let mode: String?

    /// File contents for `writeFile`. Supports `${var}` template expansion.
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
        case .mkdir:
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
