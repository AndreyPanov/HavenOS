import Foundation

/// Maps facade operations to a specific backend engine.
///
/// Each capability type (Books, Files, Music) will have its own adapter
/// implementation that knows how to provision, configure, and query the
/// underlying service (e.g. KavitaAdapter, FileBrowserAdapter).
///
/// The ``GenericAdapter`` provides a default implementation that wraps
/// standard start/stop/open lifecycle for capabilities without custom adapters.
public protocol BackendAdapter: Sendable {
    /// One-time setup after install (e.g. write config, set library path).
    func provision(settings: [String: String]) async throws

    /// Push updated settings to the backend.
    func applySettings(_ settings: [String: String]) async throws

    /// Execute a backend-specific action (e.g. rescan library).
    func triggerAction(_ action: CapabilityAction) async throws

    /// Read current health from the backend.
    func readHealth() async -> CapabilityHealth

    /// URL for the backend's own web UI, if any.
    var advancedURL: URL? { get }
}
