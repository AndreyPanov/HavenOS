import Foundation

// MARK: - Domain Model

/// Haven-native representation of a book library.
/// Backend-independent — no Kavita, Calibre, or other engine terms.
public struct BooksLibrary: Sendable, Equatable {
    /// Paths to the book library folders on disk.
    public let libraryPaths: [String]
    /// Current scan/index status.
    public let scanStatus: ScanStatus
    /// Total number of items (nil if unknown or not yet scanned).
    public let itemCount: Int?

    /// Primary library path (first one).
    public var libraryPath: String {
        libraryPaths.first ?? "~/Books"
    }

    public init(libraryPaths: [String], scanStatus: ScanStatus = .idle, itemCount: Int? = nil) {
        self.libraryPaths = libraryPaths
        self.scanStatus = scanStatus
        self.itemCount = itemCount
    }

    public init(libraryPath: String, scanStatus: ScanStatus = .idle, itemCount: Int? = nil) {
        self.libraryPaths = [libraryPath]
        self.scanStatus = scanStatus
        self.itemCount = itemCount
    }
}

/// Whether the backend needs additional setup before it can report
/// library data. The meaning varies by backend — could be auth,
/// first-run config, or nothing at all.
public enum BackendSetupState: Sendable, Equatable {
    /// Backend is ready — no setup needed.
    case ready
    /// Backend needs user action before it can operate.
    case needsSetup(message: String)
    /// Setup is in progress.
    case settingUp
    /// Setup failed.
    case failed(String)
}

// MARK: - Facade Protocol

/// Facade for book library capabilities.
///
/// Implementations map this interface to a specific backend
/// (e.g. Kavita, Calibre-Web). The UI programs against this
/// protocol and never references the backend directly.
@MainActor
public protocol BooksFacade: ConnectableFacade {
    /// Current library state (nil before first provision).
    var library: BooksLibrary? { get }

    /// Set or change the primary library path on disk.
    func setLibraryPath(_ path: String) async throws

    /// Add an additional library folder.
    func addLibraryPath(_ path: String) async throws

    /// Remove a library folder by path.
    func removeLibraryPath(_ path: String) async throws

    /// Trigger a library rescan.
    func rescan() async throws
}
