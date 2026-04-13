import Foundation

/// Errors that can occur during file provisioning.
public enum ProvisionError: Error, LocalizedError {
    /// The resolved destination path escapes the service root directory.
    case pathEscapesServiceRoot(destination: String, serviceRoot: String)

    /// The download from the source URL failed.
    case downloadFailed(source: String, detail: String)

    /// Writing the downloaded file to the destination failed.
    case writeFailed(destination: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .pathEscapesServiceRoot(let dest, let root):
            "Provision destination '\(dest)' escapes service root '\(root)'."
        case .downloadFailed(let source, let detail):
            "Failed to download provision from '\(source)': \(detail)"
        case .writeFailed(let dest, let detail):
            "Failed to write provision to '\(dest)': \(detail)"
        }
    }
}
