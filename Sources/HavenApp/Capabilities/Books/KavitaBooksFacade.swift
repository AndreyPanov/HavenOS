import Foundation
import HavenFacade
import HavenCore
import os

private let log = Logger(subsystem: "com.haven", category: "KavitaBooksFacade")

/// Books facade backed by Kavita.
///
/// Connects to the Kavita REST API to provide library state,
/// item counts, and scan triggers — all surfaced through the
/// backend-independent ``BooksFacade`` protocol.
///
/// Auth (connect/disconnect) is Kavita-specific and lives here,
/// not on the protocol. The UI discovers it via `setupState` and
/// uses a type check on the concrete class for the connect sheet.
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
        case .disconnected:
            return .needsSetup(message: "Connect to see your library")
        case .connecting:
            return .settingUp
        case .connected:
            return .ready
        case .failed(let msg):
            return .failed(msg)
        }
    }

    // MARK: - Kavita-Specific (Auth)

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var itemCount: Int?

    var connectedUsername: String? {
        UserDefaults.standard.string(forKey: usernameKey)
    }

    // MARK: - Internal

    private weak var serviceManager: ServiceManager?
    private var apiClient: KavitaAPIClient?
    private var authToken: String?
    private var port: Int?

    // MARK: - Init

    init(capabilityID: String, serviceManager: ServiceManager) {
        self.capabilityID = capabilityID
        self.serviceManager = serviceManager
        refresh()
        loadSavedToken()
    }

    // MARK: - Available Actions

    var availableActions: [CapabilityAction] {
        switch state {
        case .ready:
            var actions: [CapabilityAction] = []
            if connectionState == .connected {
                actions.append(.rescan)
            }
            if advancedURL != nil {
                actions.append(.openInBrowser)
            }
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
        guard let sm = serviceManager else { return }

        switch action.id {
        case CapabilityAction.start.id:
            await sm.startService(capabilityID: capabilityID)
        case CapabilityAction.stop.id:
            await sm.stopService(capabilityID: capabilityID)
        case CapabilityAction.restart.id:
            await sm.stopService(capabilityID: capabilityID)
            await sm.startService(capabilityID: capabilityID)
        case CapabilityAction.remove.id:
            await sm.uninstallService(capabilityID: capabilityID)
        case CapabilityAction.rescan.id:
            try await rescan()
        default:
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
        guard let sm = serviceManager else { return }
        guard let service = sm.installedServices.first(where: { $0.id == capabilityID }) else {
            state = .idle
            health = .unknown
            advancedURL = nil
            library = nil
            return
        }

        let stored = sm.storedState(for: capabilityID)
        let libraryPath = stored?.resolvedSettings["library_path"] ?? "~/Books"
        port = service.port

        if let p = port {
            apiClient = KavitaAPIClient(port: p)
            advancedURL = URL(string: "http://localhost:\(p)")
        }

        switch service.status {
        case .running:
            state = .ready
            health = .healthy
        case .stopped:
            state = .idle
            health = .unknown
            connectionState = .disconnected
        case .failed:
            state = .error("Service failed")
            health = CapabilityHealth(status: .unhealthy, message: "Service failed")
            connectionState = .disconnected
        case .installing:
            state = .starting
            health = .unknown
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
