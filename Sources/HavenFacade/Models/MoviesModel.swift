import Foundation

// MARK: - Domain Model

/// Haven-native representation of a movie/TV library.
/// Backend-independent — no Jellyfin, Emby, or other engine terms.
public struct MoviesLibrary: Sendable, Equatable {
    /// Paths to the movies library folders on disk.
    public let libraryPaths: [String]
    /// Current scan/index status.
    public let scanStatus: ScanStatus
    /// Number of movies (nil if unknown).
    public let movieCount: Int?
    /// Number of TV shows (nil if unknown).
    public let showCount: Int?

    /// Primary library path (first one).
    public var libraryPath: String {
        libraryPaths.first ?? "~/Movies"
    }

    public init(
        libraryPaths: [String],
        scanStatus: ScanStatus = .idle,
        movieCount: Int? = nil,
        showCount: Int? = nil
    ) {
        self.libraryPaths = libraryPaths
        self.scanStatus = scanStatus
        self.movieCount = movieCount
        self.showCount = showCount
    }
}

/// Phases of the initial setup wizard for a movies backend.
/// Drives the progressive inline UI — each phase maps to a card
/// that appears (with animation) in the setup flow.
public enum SetupPhase: Sendable, Equatable {
    /// Waiting for the backend server to become reachable.
    case waitingForServer
    /// Creating the admin account automatically.
    case creatingAccount
    /// Waiting for the user to pick a library folder.
    case awaitingLibraryPath
    /// Waiting for the user to choose library content type.
    case awaitingLibraryType
    /// Creating the library on the backend.
    case creatingLibrary
    /// Library scan in progress (progress percentage if available).
    case scanning(progress: Double?)
    /// Setup complete — ready to transition to normal view.
    case complete
}

/// Content type for the movies library.
public enum LibraryContentType: String, Sendable, Equatable, CaseIterable {
    case moviesAndShows = "mixed"
    case moviesOnly = "movies"
    case showsOnly = "shows"

    public var label: String {
        switch self {
        case .moviesAndShows: "Movies & TV Shows"
        case .moviesOnly: "Movies only"
        case .showsOnly: "TV Shows only"
        }
    }
}

// MARK: - Facade Protocol

/// Facade for movies/TV library capabilities.
///
/// Implementations map this interface to a specific backend
/// (e.g. Jellyfin). The UI programs against this protocol
/// and never references the backend directly.
@MainActor
public protocol MoviesFacade: ConnectableFacade {
    /// Current library state (nil before first provision).
    var library: MoviesLibrary? { get }

    /// Current setup wizard phase (nil when setup is complete or not needed).
    var setupPhase: SetupPhase? { get }

    /// Set or change the movies library path on disk.
    func setLibraryPath(_ path: String, contentType: LibraryContentType) async throws

    /// Add an additional library folder.
    func addLibraryPath(_ path: String) async throws

    /// Remove a library folder by path.
    func removeLibraryPath(_ path: String) async throws

    /// Advance the setup wizard from folder selection to content type selection.
    func confirmLibraryFolder()

    /// Trigger a library rescan (metadata refresh).
    func rescan() async throws
}
