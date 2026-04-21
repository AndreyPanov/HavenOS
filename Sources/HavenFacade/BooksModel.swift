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

    /// Set or change the library path on disk.
    func setLibraryPath(_ path: String) async throws

    /// Trigger a library rescan.
    func rescan() async throws
}
