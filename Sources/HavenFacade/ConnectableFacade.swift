import Foundation

/// Connection state for capabilities that authenticate with a backend.
public enum ConnectionState: Sendable, Equatable {
    case disconnected, connecting, connected, failed(String)
}

/// Device access credentials for streaming/reading on other devices.
public struct DeviceAccessInfo: Sendable, Equatable {
    /// LAN-accessible server address (e.g. `http://MacBook-Pro.local:4533`).
    public let serverAddress: String
    /// Username for authentication (if required by the protocol).
    public let username: String?
    /// Password for authentication (if required by the protocol).
    public let password: String?
    /// Token-based URL that doesn't require separate login (e.g. OPDS with API key).
    public let tokenURL: String?

    public init(
        serverAddress: String,
        username: String? = nil,
        password: String? = nil,
        tokenURL: String? = nil
    ) {
        self.serverAddress = serverAddress
        self.username = username
        self.password = password
        self.tokenURL = tokenURL
    }
}

/// Facade extension for capabilities that require user authentication.
///
/// Both Books and Music backends share the same connection lifecycle:
/// managed mode (Haven auto-provisions account) vs custom mode (user signs in).
/// Views program against this protocol — no backend downcasts needed.
@MainActor
public protocol ConnectableFacade: CapabilityFacade {
    /// Whether the backend needs additional setup (auth, config, etc.).
    var setupState: BackendSetupState { get }

    /// Current connection state.
    var connectionState: ConnectionState { get }

    /// True while auto-connect is in progress.
    var isAutoConnecting: Bool { get }

    /// True after auto-connect exhausted all methods.
    var autoConnectExhausted: Bool { get }

    /// Whether Haven manages the account automatically.
    var isManagedByHaven: Bool { get set }

    /// Username of the connected account (nil if not connected).
    var connectedUsername: String? { get }

    /// Device access info for streaming/reading on other devices (nil if not available).
    var deviceAccessInfo: DeviceAccessInfo? { get }

    /// Backend display name (e.g. "Kavita", "Navidrome") — for "Powered by" labels.
    var backendName: String { get }

    /// Scan errors from the last library scan (empty if none).
    var scanErrors: [String] { get }

    /// Create a new admin account on the backend.
    func createAccount(username: String, password: String) async throws

    /// Sign in with existing credentials.
    func connect(username: String, password: String) async throws

    /// Disconnect the current session (preserves managed credentials).
    func disconnect()

    /// Fully sign out and clear all stored credentials.
    func signOut()

    /// Switch to Haven-managed account mode.
    func switchToManaged()

    /// Switch to custom (user-managed) account mode.
    func switchToCustom()

    /// Retry auto-connect.
    func autoConnect() async
}
