import Foundation

/// Errors that can occur during install step execution.
public enum InstallStepError: Error, LocalizedError, Sendable {
    /// A step failed to execute.
    case stepFailed(action: String, path: String, detail: String)

    /// A path in an install step escapes the allowed root directory.
    case pathEscapesRoot(path: String, root: String)

    /// A required source field was missing.
    case missingSource(action: String, path: String)

    public var errorDescription: String? {
        switch self {
        case .stepFailed(let action, let path, let detail):
            "Install step '\(action)' failed for '\(path)': \(detail)"
        case .pathEscapesRoot(let path, let root):
            "Install step path '\(path)' escapes root '\(root)'."
        case .missingSource(let action, let path):
            "Install step '\(action)' for '\(path)' requires a source."
        }
    }
}
