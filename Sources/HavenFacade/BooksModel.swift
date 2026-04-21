import Foundation

// MARK: - Domain Model

/// Haven-native representation of a book library.
/// Backend-independent — no Kavita, Calibre, or other engine terms.
public struct BooksLibrary: Sendable, Equatable {
    /// Path to the book library on disk.
    public let libraryPath: String
    /// Current scan/index status.
    public let scanStatus: ScanStatus
    /// Total number of books (nil if unknown or not yet scanned).
    public let itemCount: Int?

    public init(libraryPath: String, scanStatus: ScanStatus = .idle, itemCount: Int? = nil) {
        self.libraryPath = libraryPath
        self.scanStatus = scanStatus
        self.itemCount = itemCount
    }
}

/// Connection state for backends that require authentication.
public enum LibraryConnectionState: Sendable, Equatable {
    /// Not connected — credentials not yet provided.
    case disconnected
    /// Connection in progress.
    case connecting
    /// Connected and authenticated.
    case connected
    /// Connection failed.
    case failed(String)
}

// MARK: - Facade Protocol

/// Facade for book library capabilities.
///
/// Implementations map this interface to a specific backend
/// (e.g. Kavita, Calibre-Web). The UI programs against this
/// protocol and never references the backend directly.
@MainActor
public protocol BooksFacade: CapabilityFacade {
    /// Current library state (nil before first provision).
    var library: BooksLibrary? { get }

    /// Connection state (backends that require auth).
    var connectionState: LibraryConnectionState { get }

    /// Number of series/items in the library (nil if unknown).
    var seriesCount: Int? { get }

    /// Display name of the connected account (nil if not connected).
    var connectedUsername: String? { get }

    /// Set or change the library path on disk.
    func setLibraryPath(_ path: String) async throws

    /// Trigger a library rescan.
    func rescan() async throws

    /// Authenticate with the backend service.
    func connect(username: String, password: String) async throws

    /// Disconnect from the backend service.
    func disconnect()
}
