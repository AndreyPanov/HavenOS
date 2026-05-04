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

/// A user-facing file or folder item inside a configured Files root.
public struct FilesItem: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case folder
        case file
    }

    public let id: String
    public let name: String
    public let path: String
    public let kind: Kind
    public let byteCount: Int64?
    public let modifiedAt: Date?

    public init(
        id: String? = nil,
        name: String,
        path: String,
        kind: Kind,
        byteCount: Int64? = nil,
        modifiedAt: Date? = nil
    ) {
        self.id = id ?? path
        self.name = name
        self.path = path
        self.kind = kind
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }
}

/// Current native browsing state for a Files capability.
public struct FilesFolderState: Sendable, Equatable {
    public let root: FilesRoot?
    public let currentPath: String?
    public let items: [FilesItem]
    public let errorMessage: String?

    public init(
        root: FilesRoot?,
        currentPath: String?,
        items: [FilesItem] = [],
        errorMessage: String? = nil
    ) {
        self.root = root
        self.currentPath = currentPath
        self.items = items
        self.errorMessage = errorMessage
    }
}

// MARK: - Facade Protocol

/// Facade for file management capabilities.
///
/// Implementations map this interface to a specific backend
/// (e.g. FileBrowser). The UI programs against this protocol
/// and never references the backend directly.
@MainActor
public protocol FilesFacade: ConnectableFacade {
    /// Configured root directories.
    var roots: [FilesRoot] { get }

    /// Current native browsing state.
    var folderState: FilesFolderState { get }

    /// Open the given root in the native browser.
    func openRoot(_ root: FilesRoot) async

    /// Add another root directory to the native and device-access file set.
    func addRoot(path: String) async throws

    /// Remove a configured root directory. Implementations should keep at least one root.
    func removeRoot(_ root: FilesRoot) async throws

    /// Open a child folder in the native browser.
    func openFolder(_ item: FilesItem) async

    /// Navigate to the parent folder, if still inside the selected root.
    func navigateUp() async

    /// Refresh the current folder listing.
    func refreshItems() async

    /// Create a folder in the current directory.
    func createFolder(named name: String) async throws

    /// Rename a file or folder in place.
    func rename(_ item: FilesItem, to newName: String) async throws

    /// Move a file or folder to the macOS Trash.
    func moveToTrash(_ item: FilesItem) async throws
}
