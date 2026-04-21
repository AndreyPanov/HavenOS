import Foundation

// MARK: - Domain Model

/// A user-visible root directory in a file management capability.
/// Backend-independent — no FileBrowser or other engine terms.
public struct FilesRoot: Sendable, Equatable, Identifiable {
    public let id: String
    /// Absolute path on disk.
    public let path: String
    /// User-facing label.
    public let label: String

    public init(id: String = UUID().uuidString, path: String, label: String) {
        self.id = id
        self.path = path
        self.label = label
    }
}

// MARK: - Facade Protocol

/// Facade for file management capabilities.
///
/// Implementations map this interface to a specific backend
/// (e.g. FileBrowser). The UI programs against this protocol
/// and never references the backend directly.
@MainActor
public protocol FilesFacade: CapabilityFacade {
    /// Configured root directories.
    var roots: [FilesRoot] { get }

    /// Set the root directory for file browsing.
    func setRoot(_ path: String) async throws
}
