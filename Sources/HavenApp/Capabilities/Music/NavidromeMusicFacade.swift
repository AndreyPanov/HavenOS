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
package final class NavidromeMusicFacade: MusicFacade {
    package let capabilityID: String

    // MARK: - CapabilityFacade

    package private(set) var state: CapabilityState = .idle
    package private(set) var health: CapabilityHealth = .unknown
    package private(set) var advancedURL: URL?

    // MARK: - MusicFacade

    package private(set) var library: MusicLibrary?
    package var setupPhase: SetupPhase?

    package var setupState: BackendSetupState {
        if setupPhase != nil { return .settingUp }
        switch connectionState {
        case .disconnected: return .needsSetup(message: "Connect to see your library")
        case .connecting:   return .settingUp
        case .connected:    return .ready
        case .failed(let m): return .failed(m)
        }
    }

    // MARK: - Connection State

    package private(set) var connectionState: ConnectionState = .disconnected

    /// True while auto-connect is in progress.
    package private(set) var isAutoConnecting = false

    /// True after auto-connect exhausted all methods.
    package private(set) var autoConnectExhausted = false

    /// User preference: true = Haven manages the account automatically.
    package var isManagedByHaven: Bool {
        get { !UserDefaults.standard.bool(forKey: customAccountKey) }
        set { UserDefaults.standard.set(!newValue, forKey: customAccountKey) }
    }

    package var connectedUsername: String? {
        guard connectionState == .connected else { return nil }
        return UserDefaults.standard.string(forKey: usernameKey)
    }

    package var connectedPassword: String? {
        guard connectionState == .connected else { return nil }
        return UserDefaults.standard.string(forKey: passwordKey)
    }

    package var hasSavedCredentials: Bool {
        UserDefaults.standard.string(forKey: tokenKey) != nil
    }

    // MARK: - ConnectableFacade

    package let backendName = "Navidrome"

    package var scanErrors: [String] { [] }

    package var deviceAccessInfo: DeviceAccessInfo? {
        guard let p = port, connectionState == .connected else { return nil }
        let hostname = ProcessInfo.processInfo.hostName
        let address = "http://\(hostname):\(p)"
        return DeviceAccessInfo(
            serverAddress: address,
            username: connectedUsername,
            password: connectedPassword
        )
    }

    // MARK: - Device Access

    /// LAN-accessible server address (e.g. `http://MacBook-Pro.local:4533`).
    package var serverAddress: String? {
        guard let p = port else { return nil }
        let hostname = ProcessInfo.processInfo.hostName
        return "http://\(hostname):\(p)"
    }

    // MARK: - Library Stats

    package private(set) var artistCount: Int?
    package private(set) var albumCount: Int?
    package private(set) var trackCount: Int?

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

    package init(capabilityID: String, serviceManager: ServiceManager) {
        self.capabilityID = capabilityID
        self.serviceManager = serviceManager
        self.lifecycle = FacadeLifecycle(serviceManager: serviceManager)
        refresh()
    }

    // MARK: - Available Actions

    package var availableActions: [CapabilityAction] {
        switch state {
        case .ready:
            var actions: [CapabilityAction] = []
            if connectionState == .connected { actions.append(.rescan) }
            if advancedURL != nil { actions.append(.openInBrowser) }
            actions.append(.remove)
            return actions
        case .idle, .error:
            return [.start, .remove]
        case .starting, .degraded:
            return []
        }
    }

    // MARK: - Perform Actions

    package func perform(_ action: CapabilityAction) async throws {
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

    package func setLibraryPath(_ path: String) async throws {
        throw FacadeError.adapterError("Changing music folder requires reinstalling the service with new settings.")
    }

    package func addLibraryPath(_ path: String) async throws {
        guard let client = apiClient, let token = authToken else {
            throw FacadeError.adapterError("Not connected")
        }

        var paths = resolvedLibraryPaths
        let expandedPath = (path as NSString).expandingTildeInPath
        guard !paths.contains(path) && !paths.contains(expandedPath) else { return }

        let fm = FileManager.default
        if !fm.fileExists(atPath: expandedPath) {
            try fm.createDirectory(atPath: expandedPath, withIntermediateDirectories: true)
        }

        try await client.createLibrary(
            name: libraryName(for: expandedPath),
            path: expandedPath,
            token: token
        )

        paths.append(path)
        saveLibraryPaths(paths)
        log.info("Added music library folder: \(path)")

        updateLibrary()
        try await rescan()
    }

    package func removeLibraryPath(_ path: String) async throws {
        guard let client = apiClient, let token = authToken else {
            throw FacadeError.adapterError("Not connected")
        }

        var paths = resolvedLibraryPaths
        let expandedPath = (path as NSString).expandingTildeInPath
        guard paths.count > 1 else {
            throw FacadeError.adapterError("Cannot remove the last folder")
        }
        guard let first = paths.first,
              (first as NSString).expandingTildeInPath != expandedPath else {
            throw FacadeError.adapterError("The primary music folder is set in the service configuration and cannot be removed without reinstalling.")
        }

        let libraries = try await client.getLibraries(token: token)
        guard let library = libraries.first(where: {
            guard let libraryPath = $0.path else { return false }
            return (libraryPath as NSString).expandingTildeInPath == expandedPath
        }), let id = library.id else {
            throw FacadeError.adapterError("Navidrome library not found for this folder")
        }

        try await client.deleteLibrary(id: id, token: token)
        paths.removeAll { $0 == path || ($0 as NSString).expandingTildeInPath == expandedPath }
        saveLibraryPaths(paths)
        log.info("Removed music library folder: \(path)")

        updateLibrary()
        try await rescan()
    }

    package func rescan() async throws {
        guard let client = apiClient else {
            throw FacadeError.adapterError("Not connected")
        }
        guard let username = UserDefaults.standard.string(forKey: usernameKey),
              let password = UserDefaults.standard.string(forKey: passwordKey) else {
            throw FacadeError.adapterError("No credentials for scan")
        }
        guard currentScanStatus != .scanning else { return }
        log.info("Triggering library rescan")
        currentScanStatus = .scanning
        updateLibrary()

        do {
            try await client.startScan(username: username, password: password)
        } catch {
            log.warning("Scan API failed: \(error.localizedDescription)")
            currentScanStatus = .idle
            updateLibrary()
            throw error
        }

        // Poll scan status until done, then refresh stats
        scanPollTask?.cancel()
        scanPollTask = Task {
            try? await Task.sleep(for: .seconds(2))

            for i in 1...30 {
                guard !Task.isCancelled else { return }
                do {
                    let status = try await client.getScanStatus(username: username, password: password)
                    if !status.scanning {
                        log.info("Scan complete (\(status.count) tracks)")
                        break
                    }
                    log.debug("Scan poll \(i)/30: scanning (\(status.count) tracks so far)")
                } catch {
                    log.warning("Scan poll failed: \(error.localizedDescription)")
                    break
                }
                try? await Task.sleep(for: .seconds(2))
            }

            // Brief delay for Navidrome to finalize counts after scan
            try? await Task.sleep(for: .seconds(1))
            await self.fetchLibraryStats()
            self.currentScanStatus = .idle
            self.updateLibrary()
            if case .scanning = self.setupPhase {
                self.setupPhase = nil
            }
            log.info("Rescan finished")
        }
    }

    // MARK: - Auto-Connect

    /// Two flows:
    /// - **Returning user** (has saved credentials): silent reconnect, no wizard.
    /// - **First run** (no credentials): progressive wizard with account choice.
    package func autoConnect() async {
        guard let client = apiClient else { return }
        connectionState = .connecting
        log.info("Auto-connect: waiting for Navidrome API...")

        // Step 1: Poll /ping until reachable
        setupPhase = .waitingForServer
        let healthy = await pollHealth(client: client, maxAttempts: 15, interval: 1.0)
        guard healthy, !Task.isCancelled else {
            if !Task.isCancelled {
                log.warning("Auto-connect: Navidrome API not reachable after polling")
                connectionState = .failed("Service is starting — try again in a moment")
            }
            setupPhase = nil
            isAutoConnecting = false
            return
        }
        log.info("Auto-connect: Navidrome API is healthy")

        // Step 2: Try saved credentials (returning user — skip wizard)
        if await tryExistingCredentials(client: client) {
            setupPhase = nil
            isAutoConnecting = false
            return
        }

        // Step 3: First run — show account choice
        setupPhase = .awaitingAccountChoice
        isAutoConnecting = false
        log.info("Auto-connect: first run, awaiting account choice")
    }

    /// User chose "Set it up for me" during setup wizard.
    package func chooseManaged() {
        guard setupPhase == .awaitingAccountChoice else { return }
        isManagedByHaven = true
        setupPhase = .creatingAccount

        autoConnectTask = Task {
            guard let client = apiClient else { return }

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
                log.info("Setup wizard: created managed account")
            } catch {
                log.info("Setup wizard: admin creation failed, trying login: \(error.localizedDescription)")
                if let mUser = UserDefaults.standard.string(forKey: managedUsernameKey),
                   let mPass = UserDefaults.standard.string(forKey: managedPasswordKey),
                   let response = try? await client.login(username: mUser, password: mPass) {
                    authToken = response.token
                    connectionState = .connected
                    saveCredentials(response.token, username: mUser)
                    log.info("Setup wizard: logged in with existing managed credentials")
                } else {
                    setupPhase = nil
                    connectionState = .failed("Couldn't create account — try signing in manually")
                    return
                }
            }

            setupPhase = .awaitingLibraryPath
            log.info("Setup wizard: awaiting library path")
        }
    }

    /// User chose "I have my own account".
    package func chooseCustom() {
        guard setupPhase == .awaitingAccountChoice else { return }
        isManagedByHaven = false
        // View will show ConnectSheet; after connect() succeeds, call continueSetupAfterLogin()
    }

    /// Called after manual connect() to finish setup.
    package func continueSetupAfterLogin() {
        if setupPhase == .awaitingAccountChoice || setupPhase == nil {
            setupPhase = .awaitingLibraryPath
            log.info("Setup wizard: manual login succeeded, awaiting library path")
        }
    }

    /// User confirmed a music folder during setup.
    package func confirmSetupFolder(_ path: String) async throws {
        guard setupPhase == .awaitingLibraryPath else { return }
        let expandedPath = (path as NSString).expandingTildeInPath
        guard !expandedPath.isEmpty else {
            throw FacadeError.adapterError("Choose a music folder.")
        }

        setupPhase = .creatingLibrary
        let fm = FileManager.default
        if !fm.fileExists(atPath: expandedPath) {
            try fm.createDirectory(atPath: expandedPath, withIntermediateDirectories: true)
        }

        if let client = apiClient, let token = authToken {
            do {
                try await ensureLibraryExists(
                    path: expandedPath,
                    client: client,
                    token: token
                )
            } catch {
                setupPhase = .awaitingLibraryPath
                throw error
            }
        }

        saveLibraryPaths([expandedPath])
        updateLibrary()

        guard connectionState == .connected else {
            setupPhase = nil
            return
        }

        setupPhase = .scanning(progress: nil)
        do {
            try await rescan()
        } catch {
            setupPhase = nil
            throw error
        }
    }

    /// Try all saved credential methods. Returns true if connected.
    private func tryExistingCredentials(client: NavidromeAPIClient) async -> Bool {
        loadSavedCredentials()
        if let token = authToken {
            if await verifyToken(client: client, token: token) {
                connectionState = .connected
                await fetchLibraryStats()
                return true
            }
            authToken = nil
        }

        if let username = UserDefaults.standard.string(forKey: usernameKey),
           let password = UserDefaults.standard.string(forKey: passwordKey),
           let response = try? await client.login(username: username, password: password) {
            authToken = response.token
            connectionState = .connected
            saveCredentials(response.token, username: username)
            await fetchLibraryStats()
            return true
        }

        if let mUser = UserDefaults.standard.string(forKey: managedUsernameKey),
           let mPass = UserDefaults.standard.string(forKey: managedPasswordKey),
           let response = try? await client.login(username: mUser, password: mPass) {
            authToken = response.token
            connectionState = .connected
            saveCredentials(response.token, username: mUser)
            UserDefaults.standard.set(mPass, forKey: passwordKey)
            await fetchLibraryStats()
            return true
        }

        return false
    }

    private func pollHealth(client: NavidromeAPIClient, maxAttempts: Int, interval: TimeInterval) async -> Bool {
        for attempt in 1...maxAttempts {
            if Task.isCancelled { return false }
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
            _ = try await client.getLibraryInfo(token: token)
            return true
        } catch {
            return false
        }
    }

    private func ensureLibraryExists(
        path: String,
        client: NavidromeAPIClient,
        token: String
    ) async throws {
        let expandedPath = (path as NSString).expandingTildeInPath
        let libraries = try await client.getLibraries(token: token)
        let hasLibrary = libraries.contains { library in
            guard let libraryPath = library.path else { return false }
            return (libraryPath as NSString).expandingTildeInPath == expandedPath
        }
        guard !hasLibrary else { return }

        try await client.createLibrary(
            name: libraryName(for: expandedPath),
            path: expandedPath,
            token: token
        )
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

    package func createAccount(username: String, password: String) async throws {
        guard let client = apiClient else {
            throw FacadeError.adapterError("Service is not running")
        }

        connectionState = .connecting
        do {
            let response = try await client.createAdmin(username: username, password: password)
            authToken = response.token
            connectionState = .connected
            saveCredentials(response.token, username: username)
            isManagedByHaven = false
            UserDefaults.standard.removeObject(forKey: passwordKey)
            log.info("Created Navidrome admin account: \(username)")
            await fetchLibraryStats()
        } catch {
            connectionState = .failed(error.localizedDescription)
            authToken = nil
            throw error
        }
    }

    package func connect(username: String, password: String) async throws {
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

    package func disconnect() {
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
        setupPhase = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        updateLibrary()
    }

    package func signOut() {
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
        setupPhase = nil
        clearAllCredentials()
        updateLibrary()
    }

    package func switchToManaged() {
        isManagedByHaven = true
        autoConnectExhausted = false
        disconnect()
        if state == .ready {
            autoConnectTask = Task { await autoConnect() }
        }
    }

    package func switchToCustom() {
        isManagedByHaven = false
        disconnect()
    }

    // MARK: - Refresh

    package func refresh() {
        let result = lifecycle.refreshState(for: capabilityID)
        state = result.state
        health = result.health
        advancedURL = result.advancedURL

        guard let service = result.service else {
            // Service uninstalled — cancel any running auto-connect
            autoConnectTask?.cancel()
            autoConnectTask = nil
            isAutoConnecting = false
            autoConnectExhausted = false
            setupPhase = nil
            if connectionState != .disconnected {
                connectionState = .disconnected
            }
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
            libraryPaths: resolvedLibraryPaths,
            scanStatus: currentScanStatus,
            artistCount: artistCount,
            albumCount: albumCount,
            trackCount: trackCount
        )

        // Auto-connect when service is ready
        if state == .ready && connectionState == .disconnected && !isAutoConnecting && !autoConnectExhausted {
            if isManagedByHaven {
                autoConnectTask?.cancel()
                isAutoConnecting = true
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

        // Retry up to 3 times with delay — Navidrome may need a moment after login
        for attempt in 1...3 {
            do {
                let info = try await client.getLibraryInfo(token: token)
                artistCount = info.totalArtists
                albumCount = info.totalAlbums
                trackCount = info.totalSongs
                log.info("Fetched library stats: \(info.totalArtists ?? 0) artists, \(info.totalAlbums ?? 0) albums, \(info.totalSongs ?? 0) tracks")
                updateLibrary()
                return
            } catch {
                let is401 = (error as? NavidromeAPIError).flatMap {
                    if case .httpError(let code, _) = $0, code == 401 { return true }
                    return nil
                } ?? false

                if is401 && attempt < 3 {
                    log.info("Stats fetch got 401, retrying in \(attempt)s (attempt \(attempt)/3)")
                    try? await Task.sleep(for: .seconds(attempt))
                    continue
                }

                log.error("Failed to fetch library stats: \(error.localizedDescription)")
                if is401 {
                    connectionState = .failed("Session expired — reconnect")
                    authToken = nil
                    UserDefaults.standard.removeObject(forKey: tokenKey)
                }
                return
            }
        }
    }

    private func updateLibrary() {
        let paths = resolvedLibraryPaths
        library = MusicLibrary(
            libraryPaths: paths,
            scanStatus: currentScanStatus,
            artistCount: artistCount,
            albumCount: albumCount,
            trackCount: trackCount
        )
        // Ensure unified content_paths key is set for backup scope
        serviceManager?.updateResolvedSetting(for: capabilityID, key: "content_paths", value: paths.joined(separator: ";"))
    }

    // MARK: - Credential Persistence

    private var tokenKey: String { "haven.navidrome.token.\(capabilityID)" }
    private var usernameKey: String { "haven.navidrome.username.\(capabilityID)" }
    private var passwordKey: String { "haven.navidrome.password.\(capabilityID)" }
    private var managedUsernameKey: String { "haven.navidrome.managedUser.\(capabilityID)" }
    private var managedPasswordKey: String { "haven.navidrome.managedPass.\(capabilityID)" }
    private var customAccountKey: String { "haven.navidrome.customAccount.\(capabilityID)" }
    private var libraryPathKey: String { "haven.navidrome.libraryPath.\(capabilityID)" }
    private var libraryPathsKey: String { "haven.navidrome.libraryPaths.\(capabilityID)" }

    /// Resolved library path from stored settings.
    private var resolvedLibraryPath: String {
        resolvedLibraryPaths.first ?? "~/Music"
    }

    /// Resolved library paths from stored settings plus any added Navidrome libraries.
    private var resolvedLibraryPaths: [String] {
        if let saved = UserDefaults.standard.stringArray(forKey: libraryPathsKey), !saved.isEmpty {
            return saved
        }
        if let saved = UserDefaults.standard.string(forKey: libraryPathKey) {
            return [saved]
        }
        let stored = serviceManager?.storedState(for: capabilityID)
        if let unified = stored?.resolvedSettings["content_paths"], !unified.isEmpty {
            let paths = unified.split(separator: ";").map(String.init).filter { !$0.isEmpty }
            if !paths.isEmpty { return paths }
        }
        if let path = stored?.resolvedSettings["music_path"] {
            return [path]
        }
        return ["~/Music"]
    }

    private func saveLibraryPaths(_ paths: [String]) {
        UserDefaults.standard.set(paths, forKey: libraryPathsKey)
        if let first = paths.first {
            UserDefaults.standard.set(first, forKey: libraryPathKey)
            serviceManager?.updateResolvedSetting(for: capabilityID, key: "music_path", value: first)
        }
        serviceManager?.updateResolvedSetting(for: capabilityID, key: "content_paths", value: paths.joined(separator: ";"))
    }

    private func libraryName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "Music" : name
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
        UserDefaults.standard.removeObject(forKey: libraryPathKey)
        UserDefaults.standard.removeObject(forKey: libraryPathsKey)
    }
}
