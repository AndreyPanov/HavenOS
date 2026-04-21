import Foundation
import HavenFacade
import HavenCore
import os

private let log = Logger(subsystem: "com.haven", category: "KavitaBooksFacade")

/// Books facade backed by Kavita.
///
/// Auth (connect/disconnect) is Kavita-specific and lives here,
/// not on the protocol. The UI discovers it via `setupState` and
/// downcasts to this class for the connect sheet.
@MainActor
@Observable
final class KavitaBooksFacade: BooksFacade {
    let capabilityID: String

    // MARK: - CapabilityFacade

    private(set) var state: CapabilityState = .idle
    private(set) var health: CapabilityHealth = .unknown
    private(set) var advancedURL: URL?

    // MARK: - BooksFacade

    private(set) var library: BooksLibrary?

    var setupState: BackendSetupState {
        switch connectionState {
        case .disconnected: .needsSetup(message: "Connect to see your library")
        case .connecting:   .settingUp
        case .connected:    .ready
        case .failed(let m): .failed(m)
        }
    }

    // MARK: - Kavita-Specific (Auth)

    enum ConnectionState: Equatable {
        case disconnected, connecting, connected, failed(String)
    }

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var itemCount: Int?

    var connectedUsername: String? {
        UserDefaults.standard.string(forKey: usernameKey)
    }

    // MARK: - Internal

    private let lifecycle: FacadeLifecycle
    private weak var serviceManager: ServiceManager?
    private var apiClient: KavitaAPIClient?
    private var authToken: String?
    private var port: Int?

    // MARK: - Init

    init(capabilityID: String, serviceManager: ServiceManager) {
        self.capabilityID = capabilityID
        self.serviceManager = serviceManager
        self.lifecycle = FacadeLifecycle(serviceManager: serviceManager)
        refresh()
        loadSavedToken()
    }

    // MARK: - Available Actions

    var availableActions: [CapabilityAction] {
        switch state {
        case .ready:
            var actions: [CapabilityAction] = []
            if connectionState == .connected { actions.append(.rescan) }
            if advancedURL != nil { actions.append(.openInBrowser) }
            actions.append(contentsOf: [.stop, .restart, .remove])
            return actions
        case .idle, .error:
            return [.start, .remove]
        case .starting, .degraded:
            return []
        }
    }

    // MARK: - Perform Actions

    func perform(_ action: CapabilityAction) async throws {
        if action.id == CapabilityAction.rescan.id {
            try await rescan()
            return
        }
        let handled = try await lifecycle.perform(action, capabilityID: capabilityID)
        if !handled {
            throw FacadeError.actionNotAvailable(action.id)
        }
    }

    // MARK: - BooksFacade Methods

    func setLibraryPath(_ path: String) async throws {
        throw FacadeError.adapterError("Changing library path requires reinstalling the service with new settings.")
    }

    func rescan() async throws {
        guard let client = apiClient, let token = authToken else {
            throw FacadeError.adapterError("Not connected")
        }
        log.info("Triggering library rescan")
        try await client.scanAllLibraries(token: token)
    }

    // MARK: - Kavita Auth

    func connect(username: String, password: String) async throws {
        guard let client = apiClient else {
            throw FacadeError.adapterError("Service is not running")
        }

        connectionState = .connecting
        do {
            let loginResponse = try await client.login(username: username, password: password)
            authToken = loginResponse.token
            connectionState = .connected
            saveToken(loginResponse.token, username: username)
            log.info("Connected to Kavita as \(username)")
            await fetchLibraryData()
        } catch {
            connectionState = .failed(error.localizedDescription)
            authToken = nil
            throw error
        }
    }

    func disconnect() {
        authToken = nil
        connectionState = .disconnected
        itemCount = nil
        clearSavedToken()
        updateLibrary()
    }

    // MARK: - Refresh

    func refresh() {
        let result = lifecycle.refreshState(for: capabilityID)
        state = result.state
        health = result.health
        advancedURL = result.advancedURL

        guard let service = result.service else {
            library = nil
            return
        }

        let stored = serviceManager?.storedState(for: capabilityID)
        let libraryPath = stored?.resolvedSettings["library_path"] ?? "~/Books"
        port = service.port

        if let p = port {
            apiClient = KavitaAPIClient(port: p)
        }

        // Reset connection on stop/fail
        if state != .ready && state != .starting {
            connectionState = .disconnected
        }

        library = BooksLibrary(
            libraryPath: libraryPath,
            scanStatus: .idle,
            itemCount: itemCount
        )

        // Auto-reconnect if we have a saved token and service is running
        if state == .ready && connectionState == .disconnected {
            loadSavedToken()
            if authToken != nil {
                connectionState = .connected
                Task { await fetchLibraryData() }
            }
        }
    }

    // MARK: - Data Fetching

    private func fetchLibraryData() async {
        guard let client = apiClient, let token = authToken else { return }

        do {
            let libraries = try await client.getLibraries(token: token)
            let count = try await client.getSeriesCount(token: token)
            itemCount = count
            log.info("Fetched library data: \(libraries.count) libraries, \(count) series")
            updateLibrary()
        } catch {
            log.error("Failed to fetch library data: \(error.localizedDescription)")
            if let apiError = error as? KavitaAPIError,
               case .httpError(let code, _) = apiError, code == 401 {
                connectionState = .failed("Session expired — reconnect")
                authToken = nil
                clearSavedToken()
            }
        }
    }

    private func updateLibrary() {
        let stored = serviceManager?.storedState(for: capabilityID)
        let libraryPath = stored?.resolvedSettings["library_path"] ?? "~/Books"
        library = BooksLibrary(
            libraryPath: libraryPath,
            scanStatus: .idle,
            itemCount: itemCount
        )
    }

    // MARK: - Token Persistence

    private var tokenKey: String { "haven.kavita.token.\(capabilityID)" }
    private var usernameKey: String { "haven.kavita.username.\(capabilityID)" }

    private func saveToken(_ token: String, username: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        UserDefaults.standard.set(username, forKey: usernameKey)
    }

    private func loadSavedToken() {
        authToken = UserDefaults.standard.string(forKey: tokenKey)
    }

    private func clearSavedToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }
}
