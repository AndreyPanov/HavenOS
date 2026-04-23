import Foundation

// MARK: - Domain Model

/// Haven-native representation of a music library.
/// Backend-independent — no Navidrome, Subsonic, or other engine terms.
public struct MusicLibrary: Sendable, Equatable {
    /// Path to the music library on disk.
    public let libraryPath: String
    /// Current scan/index status.
    public let scanStatus: ScanStatus
    /// Number of artists (nil if unknown).
    public let artistCount: Int?
    /// Number of albums (nil if unknown).
    public let albumCount: Int?
    /// Number of tracks (nil if unknown).
    public let trackCount: Int?

    public init(
        libraryPath: String,
        scanStatus: ScanStatus = .idle,
        artistCount: Int? = nil,
        albumCount: Int? = nil,
        trackCount: Int? = nil
    ) {
        self.libraryPath = libraryPath
        self.scanStatus = scanStatus
        self.artistCount = artistCount
        self.albumCount = albumCount
        self.trackCount = trackCount
    }
}

// MARK: - Facade Protocol

/// Facade for music library capabilities.
///
/// Implementations map this interface to a specific backend
/// (e.g. Navidrome). The UI programs against this protocol
/// and never references the backend directly.
@MainActor
public protocol MusicFacade: CapabilityFacade {
    /// Current music library state (nil before first provision).
    var library: MusicLibrary? { get }

    /// Backend setup state (auth, provisioning).
    var setupState: BackendSetupState { get }

    /// Set or change the music library path on disk.
    func setLibraryPath(_ path: String) async throws

    /// Trigger a library rescan.
    func rescan() async throws
}
