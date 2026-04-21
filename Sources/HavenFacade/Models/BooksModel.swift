import Foundation

// MARK: - Domain Model

/// Haven-native representation of a book library.
/// Backend-independent — no Kavita, Calibre, or other engine terms.
public struct BooksLibrary: Sendable, Equatable {
    /// Path to the book library on disk.
    public let libraryPath: String
    /// Current scan/index status.
    public let scanStatus: ScanStatus
    /// Total number of items (nil if unknown or not yet scanned).
    public let itemCount: Int?

    public init(libraryPath: String, scanStatus: ScanStatus = .idle, itemCount: Int? = nil) {
        self.libraryPath = libraryPath
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
///
/// Auth, connection, and backend-specific config live on the
/// concrete implementation — not here.
@MainActor
public protocol BooksFacade: CapabilityFacade {
    /// Current library state (nil before first provision).
    var library: BooksLibrary? { get }

    /// Whether the backend needs additional setup (auth, config, etc.).
    var setupState: BackendSetupState { get }

    /// Set or change the library path on disk.
    func setLibraryPath(_ path: String) async throws

    /// Trigger a library rescan.
    func rescan() async throws
}
