import Foundation
import HavenFacade
import HavenCore
import os

private let log = Logger(subsystem: "com.haven", category: "NavidromeMusicFacade")

/// Music facade backed by Navidrome.
///
/// Auth flow:
/// 1. Service starts → facade polls `/ping` until Navidrome is reachable
/// 2. Tries saved JWT token → if 401, tries saved password → if no password, creates admin account
/// 3. If all fail, shows "Sign In" for manual entry
@MainActor
@Observable
final class NavidromeMusicFacade: MusicFacade {
    let capabilityID: String

    // MARK: - CapabilityFacade

    private(set) var state: CapabilityState = .idle
    private(set) var health: CapabilityHealth = .unknown
    private(set) var advancedURL: URL?

    // MARK: - MusicFacade

    private(set) var library: MusicLibrary?

    var setupState: BackendSetupState {
        switch connectionState {
        case .disconnected: .needsSetup(message: "Connect to see your library")
        case .connecting:   .settingUp
        case .connected:    .ready
        case .failed(let m): .failed(m)
        }
    }

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected, connecting, connected, failed(String)
    }

    private(set) var connectionState: ConnectionState = .disconnected

    /// True while auto-connect is in progress.
    private(set) var isAutoConnecting = false

    /// True after auto-connect exhausted all methods.
    private var autoConnectExhausted = false

    /// User preference: true = Haven manages the account automatically.
    var isManagedByHaven: Bool {
        get { !UserDefaults.standard.bool(forKey: customAccountKey) }
        set { UserDefaults.standard.set(!newValue, forKey: customAccountKey) }
    }

    var connectedUsername: String? {
        guard connectionState == .connected else { return nil }
        return UserDefaults.standard.string(forKey: usernameKey)
    }

    // MARK: - Device Access

    /// LAN-accessible server address (e.g. `http://MacBook-Pro.local:4533`).
    var serverAddress: String? {
        guard let p = port else { return nil }
        let hostname = ProcessInfo.processInfo.hostName
        return "http://\(hostname):\(p)"
    }

    // MARK: - Library Stats

    private(set) var artistCount: Int?
    private(set) var albumCount: Int?
    private(set) var trackCount: Int?

    // MARK: - Internal

    private let lifecycle: FacadeLifecycle
    private weak var serviceManager: ServiceManager?
    private var apiClient: NavidromeAPIClient?
    private var authToken: String?
    private var port: Int?
    private var autoConnectTask: Task<Void, Never>?
    private var scanPollTask: Task<Void, Never>?
    private var currentScanStatus: ScanStatus = .idle

    // MARK: - Init

    init(capabilityID: String, serviceManager: ServiceManager) {
        self.capabilityID = capabilityID
        self.serviceManager = serviceManager
        self.lifecycle = FacadeLifecycle(serviceManager: serviceManager)
        refresh()
    }

    // MARK: - Available Actions

    var availableActions: [CapabilityAction] {
        switch state {
        case .ready:
            var actions: [CapabilityAction] = []
            if connectionState == .connected { actions.append(.rescan) }
            actions.append(.remove)
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

    // MARK: - MusicFacade Methods

    func setLibraryPath(_ path: String) async throws {
        throw FacadeError.adapterError("Changing music folder requires reinstalling the service with new settings.")
    }

    func rescan() async throws {
        guard let client = apiClient, let token = authToken else {
            throw FacadeError.adapterError("Not connected")
        }
        guard currentScanStatus != .scanning else { return }
        log.info("Triggering library rescan")
        currentScanStatus = .scanning
        updateLibrary()

        try await client.scanLibrary(token: token)

        // Poll scan status until complete
        scanPollTask?.cancel()
        scanPollTask = Task {
            for _ in 1...30 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                guard let client = self.apiClient, let token = self.authToken else { return }

                if let status = try? await client.getScanStatus(token: token), !status.scanning {
                    await self.fetchLibraryStats()
                    log.info("Scan complete")
                    break
                }
            }
            self.currentScanStatus = .idle
            self.updateLibrary()
        }
    }

    // MARK: - Auto-Connect

    func autoConnect() async {
        guard let client = apiClient else { return }
        guard !isAutoConnecting else { return }

        isAutoConnecting = true
        connectionState = .connecting
        log.info("Auto-connect: waiting for Navidrome API...")

        // Step 1: Poll /ping until reachable
        let healthy = await pollHealth(client: client, maxAttempts: 15, interval: 1.0)
        guard healthy else {
            log.warning("Auto-connect: Navidrome API not reachable after polling")
            connectionState = .failed("Service is starting — try again in a moment")
            isAutoConnecting = false
            return
        }
        log.info("Auto-connect: Navidrome API is healthy")

        // Step 2: Try saved JWT token
        loadSavedCredentials()
        if let token = authToken {
            log.info("Auto-connect: trying saved token")
            if await verifyToken(client: client, token: token) {
                connectionState = .connected
                log.info("Auto-connect: saved token valid")
                await fetchLibraryStats()
                isAutoConnecting = false
                return
            }
            log.info("Auto-connect: saved token expired")
            authToken = nil
        }

        // Step 3: Try saved password
        if let username = UserDefaults.standard.string(forKey: usernameKey),
           let password = UserDefaults.standard.string(forKey: passwordKey) {
            log.info("Auto-connect: re-login with saved credentials")
            do {
                let response = try await client.login(username: username, password: password)
                authToken = response.token
                connectionState = .connected
                saveCredentials(response.token, username: username)
                log.info("Auto-connect: re-login succeeded")
                await fetchLibraryStats()
                isAutoConnecting = false
                return
            } catch {
                log.warning("Auto-connect: re-login failed: \(error.localizedDescription)")
            }
        }

        // Step 3b: Try managed credentials
        if let mUser = UserDefaults.standard.string(forKey: managedUsernameKey),
           let mPass = UserDefaults.standard.string(forKey: managedPasswordKey) {
            log.info("Auto-connect: trying managed credentials")
            do {
                let response = try await client.login(username: mUser, password: mPass)
                authToken = response.token
                connectionState = .connected
                saveCredentials(response.token, username: mUser)
                UserDefaults.standard.set(mPass, forKey: passwordKey)
                log.info("Auto-connect: managed credentials valid")
                await fetchLibraryStats()
                isAutoConnecting = false
                return
            } catch {
                log.warning("Auto-connect: managed credentials failed: \(error.localizedDescription)")
            }
        }

        // Step 4: Try to create admin account (fresh install)
        log.info("Auto-connect: attempting admin creation")
        let username = "haven"
        let password = generatePassword()
        do {
            let response = try await client.createAdmin(username: username, password: password)
            authToken = response.token
            connectionState = .connected
            saveCredentials(response.token, username: username)
            UserDefaults.standard.set(password, forKey: passwordKey)
            UserDefaults.standard.set(username, forKey: managedUsernameKey)
            UserDefaults.standard.set(password, forKey: managedPasswordKey)
            log.info("Auto-connect: created admin account")
            await fetchLibraryStats()
            isAutoConnecting = false
            return
        } catch {
            log.info("Auto-connect: admin creation failed (account exists?): \(error.localizedDescription)")
        }

        // Step 5: All methods exhausted
        connectionState = .disconnected
        isAutoConnecting = false
        autoConnectExhausted = true
        log.info("Auto-connect: giving up, manual sign-in required")
    }

    private func pollHealth(client: NavidromeAPIClient, maxAttempts: Int, interval: TimeInterval) async -> Bool {
        for attempt in 1...maxAttempts {
            if await client.isHealthy() {
                return true
            }
            log.debug("Health poll \(attempt)/\(maxAttempts): not ready")
            try? await Task.sleep(for: .seconds(interval))
        }
        return false
    }

    private func verifyToken(client: NavidromeAPIClient, token: String) async -> Bool {
        do {
            _ = try await client.getArtistCount(token: token)
            return true
        } catch {
            return false
        }
    }

    private func generatePassword() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let digits = "0123456789"
        let special = "!@#$%^&*"
        var chars: [Character] = [
            letters.randomElement()!,
            upper.randomElement()!,
            digits.randomElement()!,
            special.randomElement()!
        ]
        let all = letters + upper + digits + special
        for _ in 0..<12 { chars.append(all.randomElement()!) }
        chars.shuffle()
        return String(chars)
    }

    // MARK: - Manual Auth

    func connect(username: String, password: String) async throws {
        guard let client = apiClient else {
            throw FacadeError.adapterError("Service is not running")
        }

        connectionState = .connecting
        do {
            let response = try await client.login(username: username, password: password)
            authToken = response.token
            connectionState = .connected
            saveCredentials(response.token, username: username)
            isManagedByHaven = false
            UserDefaults.standard.removeObject(forKey: passwordKey)
            log.info("Connected to Navidrome as \(username)")
            await fetchLibraryStats()
        } catch {
            connectionState = .failed(error.localizedDescription)
            authToken = nil
            throw error
        }
    }

    func disconnect() {
        autoConnectTask?.cancel()
        autoConnectTask = nil
        scanPollTask?.cancel()
        scanPollTask = nil
        isAutoConnecting = false
        authToken = nil
        connectionState = .disconnected
        artistCount = nil
        albumCount = nil
        trackCount = nil
        currentScanStatus = .idle
        UserDefaults.standard.removeObject(forKey: tokenKey)
        updateLibrary()
    }

    func signOut() {
        autoConnectTask?.cancel()
        autoConnectTask = nil
        scanPollTask?.cancel()
        scanPollTask = nil
        isAutoConnecting = false
        authToken = nil
        connectionState = .disconnected
        artistCount = nil
        albumCount = nil
        trackCount = nil
        currentScanStatus = .idle
        clearAllCredentials()
        updateLibrary()
    }

    func switchToManaged() {
        isManagedByHaven = true
        autoConnectExhausted = false
        disconnect()
        if state == .ready {
            autoConnectTask = Task { await autoConnect() }
        }
    }

    func switchToCustom() {
        isManagedByHaven = false
        disconnect()
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

        port = service.port

        if let p = port {
            apiClient = NavidromeAPIClient(port: p)
        }

        // Reset connection when service stops
        if state != .ready && state != .starting {
            if connectionState != .disconnected {
                autoConnectTask?.cancel()
                autoConnectTask = nil
                isAutoConnecting = false
                autoConnectExhausted = false
                connectionState = .disconnected
            }
        }

        library = MusicLibrary(
            libraryPath: resolvedLibraryPath,
            scanStatus: currentScanStatus,
            artistCount: artistCount,
            albumCount: albumCount,
            trackCount: trackCount
        )

        // Auto-connect when service is ready
        if state == .ready && connectionState == .disconnected && !isAutoConnecting && !autoConnectExhausted {
            if isManagedByHaven {
                autoConnectTask = Task { await autoConnect() }
            } else {
                loadSavedCredentials()
                if authToken != nil {
                    connectionState = .connected
                    Task { await fetchLibraryStats() }
                }
            }
        }
    }

    // MARK: - Data Fetching

    private func fetchLibraryStats() async {
        guard let client = apiClient, let token = authToken else { return }

        do {
            let artists = try await client.getArtistCount(token: token)
            let albums = try await client.getAlbumCount(token: token)
            let tracks = try await client.getTrackCount(token: token)
            artistCount = artists
            albumCount = albums
            trackCount = tracks
            log.info("Fetched library stats: \(artists) artists, \(albums) albums, \(tracks) tracks")
            updateLibrary()

            // Auto-rescan on connect
            if currentScanStatus != .scanning {
                try? await rescan()
            }
        } catch {
            log.error("Failed to fetch library stats: \(error.localizedDescription)")
            if let apiError = error as? NavidromeAPIError,
               case .httpError(let code, _) = apiError, code == 401 {
                connectionState = .failed("Session expired — reconnect")
                authToken = nil
                clearAllCredentials()
            }
        }
    }

    private func updateLibrary() {
        library = MusicLibrary(
            libraryPath: resolvedLibraryPath,
            scanStatus: currentScanStatus,
            artistCount: artistCount,
            albumCount: albumCount,
            trackCount: trackCount
        )
    }

    // MARK: - Credential Persistence

    private var tokenKey: String { "haven.navidrome.token.\(capabilityID)" }
    private var usernameKey: String { "haven.navidrome.username.\(capabilityID)" }
    private var passwordKey: String { "haven.navidrome.password.\(capabilityID)" }
    private var managedUsernameKey: String { "haven.navidrome.managedUser.\(capabilityID)" }
    private var managedPasswordKey: String { "haven.navidrome.managedPass.\(capabilityID)" }
    private var customAccountKey: String { "haven.navidrome.customAccount.\(capabilityID)" }

    /// Resolved library path from stored settings.
    private var resolvedLibraryPath: String {
        let stored = serviceManager?.storedState(for: capabilityID)
        return stored?.resolvedSettings["music_path"] ?? "~/Music"
    }

    private func saveCredentials(_ token: String, username: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        UserDefaults.standard.set(username, forKey: usernameKey)
    }

    private func loadSavedCredentials() {
        authToken = UserDefaults.standard.string(forKey: tokenKey)
    }

    private func clearAllCredentials() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: passwordKey)
        UserDefaults.standard.removeObject(forKey: managedUsernameKey)
        UserDefaults.standard.removeObject(forKey: managedPasswordKey)
        UserDefaults.standard.removeObject(forKey: customAccountKey)
    }
}
