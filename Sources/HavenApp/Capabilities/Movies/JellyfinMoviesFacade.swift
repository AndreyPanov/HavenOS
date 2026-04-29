import Foundation
import HavenFacade
import HavenCore
import os

private let log = Logger(subsystem: "com.haven", category: "JellyfinMoviesFacade")

/// Movies facade backed by Jellyfin.
///
/// Setup flow (first install):
/// 1. Service starts → facade polls `/System/Ping` until Jellyfin is reachable
/// 2. Runs Jellyfin setup wizard via API (config → user → remote access → complete)
/// 3. Waits for user to pick library folder + content type (interactive)
/// 4. Creates library via API, triggers metadata scan
///
/// Reconnect flow (subsequent launches):
/// Same as Books/Music — saved token → saved password → managed creds → manual sign-in
@MainActor
@Observable
package final class JellyfinMoviesFacade: MoviesFacade {
    package let capabilityID: String

    // MARK: - CapabilityFacade

    package private(set) var state: CapabilityState = .idle
    package private(set) var health: CapabilityHealth = .unknown
    package private(set) var advancedURL: URL?

    // MARK: - MoviesFacade

    package private(set) var library: MoviesLibrary?
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
    package private(set) var isAutoConnecting = false
    package private(set) var autoConnectExhausted = false

    package var isManagedByHaven: Bool {
        get { !UserDefaults.standard.bool(forKey: customAccountKey) }
        set { UserDefaults.standard.set(!newValue, forKey: customAccountKey) }
    }

    package var connectedUsername: String? {
        guard connectionState == .connected else { return nil }
        return UserDefaults.standard.string(forKey: usernameKey)
    }

    private var connectedPassword: String? {
        guard connectionState == .connected else { return nil }
        return UserDefaults.standard.string(forKey: passwordKey)
    }

    // MARK: - ConnectableFacade

    package let backendName = "Jellyfin"
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

    // MARK: - Library Stats

    private var movieCount: Int?
    private var showCount: Int?

    // MARK: - Internal

    private let lifecycle: FacadeLifecycle
    private weak var serviceManager: ServiceManager?
    private var apiClient: JellyfinAPIClient?
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

    // MARK: - MoviesFacade Methods

    package func confirmLibraryFolder() {
        // No-op: kept for protocol conformance but folder confirmation
        // now goes directly through setLibraryPath
    }

    package func setLibraryPath(_ path: String, contentType: LibraryContentType) async throws {
        guard let client = apiClient, let token = authToken else {
            throw FacadeError.adapterError("Not connected")
        }

        let expandedPath = (path as NSString).expandingTildeInPath
        log.info("setLibraryPath: path=\(path), expanded=\(expandedPath)")

        setupPhase = .creatingLibrary

        let fm = FileManager.default
        if !fm.fileExists(atPath: expandedPath) {
            try fm.createDirectory(atPath: expandedPath, withIntermediateDirectories: true)
            log.info("setLibraryPath: created directory at \(expandedPath)")
        }

        // Remove existing libraries first (avoids duplicates on folder change)
        do {
            let existing = try await client.getLibraries(token: token)
            for lib in existing {
                try await client.removeLibrary(name: lib.Name, token: token)
                log.info("setLibraryPath: removed existing library '\(lib.Name)'")
            }
        } catch {
            log.warning("setLibraryPath: cleanup failed: \(error.localizedDescription)")
        }

        // Always create a single mixed library (handles both movies and TV shows)
        do {
            try await client.createLibrary(name: "Media", collectionType: "mixed", paths: [expandedPath], token: token)
            log.info("setLibraryPath: created Media library at \(expandedPath)")
        } catch {
            log.error("setLibraryPath: library creation failed: \(error.localizedDescription)")
            setupPhase = .awaitingLibraryPath
            throw error
        }

        saveLibraryPaths([path])
        setupPhase = .scanning(progress: nil)
        updateLibrary()

        // Start polling for scan completion
        startScanPolling()
    }

    package func addLibraryPath(_ path: String) async throws {
        guard let client = apiClient, let token = authToken else {
            throw FacadeError.adapterError("Not connected")
        }

        var paths = resolvedLibraryPaths
        let expandedPath = (path as NSString).expandingTildeInPath

        // Don't add duplicates
        guard !paths.contains(path) && !paths.contains(expandedPath) else { return }

        let fm = FileManager.default
        if !fm.fileExists(atPath: expandedPath) {
            try fm.createDirectory(atPath: expandedPath, withIntermediateDirectories: true)
        }

        // Find the existing library name to add the path to
        let libraryName = try await findLibraryName(client: client, token: token)
        try await client.addMediaPath(libraryName: libraryName, path: expandedPath, token: token)
        log.info("addLibraryPath: added \(expandedPath) to '\(libraryName)'")

        // Verify the path was actually added
        let libraries = try await client.getLibraries(token: token)
        for lib in libraries {
            log.info("addLibraryPath: library '\(lib.Name)' locations: \(lib.Locations ?? [])")
        }

        // Explicitly trigger a full library refresh
        try await client.refreshLibrary(token: token)
        log.info("addLibraryPath: triggered library refresh")

        paths.append(path)
        saveLibraryPaths(paths)
        currentScanStatus = .scanning
        updateLibrary()
        startScanPolling()
    }

    package func removeLibraryPath(_ path: String) async throws {
        guard let client = apiClient, let token = authToken else {
            throw FacadeError.adapterError("Not connected")
        }

        var paths = resolvedLibraryPaths
        let expandedPath = (path as NSString).expandingTildeInPath
        paths.removeAll { $0 == path || ($0 as NSString).expandingTildeInPath == expandedPath }

        guard !paths.isEmpty else {
            throw FacadeError.adapterError("Cannot remove the last folder")
        }

        let libraryName = try await findLibraryName(client: client, token: token)
        try await client.removeMediaPath(libraryName: libraryName, path: expandedPath, token: token)
        log.info("removeLibraryPath: removed \(expandedPath) from '\(libraryName)'")

        saveLibraryPaths(paths)
        currentScanStatus = .scanning
        updateLibrary()
        startScanPolling()
    }

    /// Find the name of the existing Jellyfin library (usually "Media").
    private func findLibraryName(client: JellyfinAPIClient, token: String) async throws -> String {
        let libraries = try await client.getLibraries(token: token)
        guard let first = libraries.first else {
            throw FacadeError.adapterError("No library found — set a library path first")
        }
        return first.Name
    }

    package func rescan() async throws {
        guard let client = apiClient, let token = authToken else {
            throw FacadeError.adapterError("Not connected")
        }
        guard currentScanStatus != .scanning else { return }
        log.info("Triggering library refresh")
        currentScanStatus = .scanning
        updateLibrary()

        do {
            try await client.refreshLibrary(token: token)
        } catch {
            log.warning("Refresh API failed: \(error.localizedDescription)")
            currentScanStatus = .idle
            updateLibrary()
            throw error
        }

        startScanPolling()
    }

    private func startScanPolling() {
        scanPollTask?.cancel()
        scanPollTask = Task {
            try? await Task.sleep(for: .seconds(5))

            // Jellyfin's "Scan Media Library" task finishes quickly (file discovery),
            // but metadata processing continues in background without a visible task.
            // Poll item counts and wait until they stabilize.
            var lastCount = 0
            var stableRounds = 0
            let stableThreshold = 3  // 3 consecutive polls with same count = done

            for i in 1...60 {
                guard !Task.isCancelled else { return }
                guard let client = self.apiClient, let token = self.authToken else { return }

                // Check scheduled tasks for progress info
                if let tasks = try? await client.getScheduledTasks(token: token) {
                    let scanTask = tasks.first { $0.State == "Running" && ($0.Name?.contains("scan") == true || $0.Name?.contains("Refresh") == true || $0.Name?.contains("library") == true) }
                    if let scanTask, let progress = scanTask.CurrentProgressPercentage {
                        self.setupPhase = .scanning(progress: progress)
                    }
                }

                // Poll item counts to detect when processing stabilizes
                if let counts = try? await client.getItemCounts(token: token) {
                    let total = counts.MovieCount + counts.SeriesCount
                    self.movieCount = counts.MovieCount
                    self.showCount = counts.SeriesCount
                    self.updateLibrary()
                    log.debug("Scan poll \(i)/60: \(counts.MovieCount) movies, \(counts.SeriesCount) shows")

                    if total == lastCount && total > 0 {
                        stableRounds += 1
                        if stableRounds >= stableThreshold {
                            log.info("Scan complete: counts stable at \(total) items")
                            break
                        }
                    } else {
                        stableRounds = 0
                        lastCount = total
                    }
                }

                try? await Task.sleep(for: .seconds(5))
            }

            await self.fetchItemCounts()
            self.currentScanStatus = .idle
            self.setupPhase = nil
            self.updateLibrary()
            log.info("Scan finished: \(self.movieCount ?? 0) movies, \(self.showCount ?? 0) shows")
        }
    }

    // MARK: - Setup Wizard

    /// Run the full Jellyfin first-run setup via API.
    private func runSetupWizard(client: JellyfinAPIClient) async -> Bool {
        log.info("Running Jellyfin setup wizard")

        // Step 1: Check if setup is already complete
        setupPhase = .waitingForServer
        do {
            let complete = try await client.isSetupComplete()
            if complete {
                log.info("Setup already complete, skipping wizard")
                setupPhase = nil
                return true
            }
        } catch {
            log.warning("Could not check setup status: \(error.localizedDescription)")
        }

        // Step 2: Configure language/metadata
        do {
            try await client.setStartupConfiguration()
            log.info("Setup wizard: configuration set")
        } catch {
            log.warning("Setup wizard: config failed: \(error.localizedDescription)")
        }

        // Step 3: Ask user how they want to manage the account
        setupPhase = .awaitingAccountChoice
        isAutoConnecting = false
        log.info("Setup wizard: awaiting account choice")
        // Wizard continues when user calls chooseManaged() or chooseCustom()
        return true
    }

    /// User chose "Set it up for me" during setup wizard.
    package func chooseManaged() {
        guard setupPhase == .awaitingAccountChoice else { return }
        isManagedByHaven = true
        setupPhase = .creatingAccount

        autoConnectTask = Task {
            guard let client = apiClient else { return }

            // Wait for user database and create admin user
            let username = "haven"
            let password = generatePassword()
            var userCreated = false
            for attempt in 1...10 {
                do {
                    let _ = try await client.getStartupUser()
                    try await client.createSetupUser(username: username, password: password)
                    log.info("Setup wizard: user created")
                    userCreated = true
                    break
                } catch {
                    log.warning("Setup wizard: user creation attempt \(attempt)/10: \(error.localizedDescription)")
                    if attempt < 10 {
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
            }
            guard userCreated else {
                setupPhase = nil
                connectionState = .failed("Couldn't create account")
                return
            }

            // Configure remote access + complete setup
            try? await client.setRemoteAccess(enableRemote: true, enableUPnP: false)
            try? await client.completeSetup()

            // Authenticate
            do {
                let response = try await client.login(username: username, password: password)
                authToken = response.AccessToken
                connectionState = .connected
                saveCredentials(response.AccessToken, username: username)
                UserDefaults.standard.set(password, forKey: passwordKey)
                UserDefaults.standard.set(username, forKey: managedUsernameKey)
                UserDefaults.standard.set(password, forKey: managedPasswordKey)
                log.info("Setup wizard: authenticated as \(username)")
            } catch {
                log.error("Setup wizard: login failed: \(error.localizedDescription)")
                setupPhase = nil
                connectionState = .failed("Login failed after account creation")
                return
            }

            // Check if libraries already exist
            if let libs = try? await client.getLibraries(token: authToken!), !libs.isEmpty {
                setupPhase = nil
                await fetchItemCounts()
                return
            }

            // Transition to folder picker
            setupPhase = .awaitingLibraryPath
            log.info("Setup wizard: awaiting library path")
        }
    }

    /// User chose "I have my own account" — they need to complete Jellyfin setup
    /// in the browser first, then sign in.
    package func chooseCustom() {
        guard setupPhase == .awaitingAccountChoice else { return }
        isManagedByHaven = false

        // Complete the Jellyfin startup wizard so the user can create their own account in the web UI
        Task {
            guard let client = apiClient else { return }
            // Wait for user DB, set a temp user so we can complete the wizard
            for _ in 1...5 {
                if let _ = try? await client.getStartupUser() { break }
                try? await Task.sleep(for: .seconds(1))
            }
            try? await client.setRemoteAccess(enableRemote: true, enableUPnP: false)
            try? await client.completeSetup()
        }

        setupPhase = nil
        // View will show ConnectSheet
    }

    /// Called after manual connect() to continue setup if needed.
    package func continueSetupAfterLogin() {
        if connectionState == .connected {
            Task {
                guard let token = authToken, let client = apiClient else { return }
                if let libs = try? await client.getLibraries(token: token), !libs.isEmpty {
                    setupPhase = nil
                    await fetchItemCounts()
                } else {
                    setupPhase = .awaitingLibraryPath
                }
            }
        }
    }

    // MARK: - Auto-Connect

    package func autoConnect() async {
        guard let client = apiClient else { return }
        connectionState = .connecting
        log.info("Auto-connect: waiting for Jellyfin API...")

        // Step 1: Poll /System/Ping until reachable
        let healthy = await pollHealth(client: client, maxAttempts: 15, interval: 1.0)
        guard healthy, !Task.isCancelled else {
            if !Task.isCancelled {
                log.warning("Auto-connect: Jellyfin API not reachable after polling")
                connectionState = .failed("Service is starting — try again in a moment")
            }
            isAutoConnecting = false
            return
        }
        log.info("Auto-connect: Jellyfin API is healthy")

        // Step 2: Check if this is a fresh install (setup wizard needed)
        // If we have saved managed credentials, setup was already done — skip wizard.
        let hasManagedCreds = UserDefaults.standard.string(forKey: managedUsernameKey) != nil
            && UserDefaults.standard.string(forKey: managedPasswordKey) != nil
        let isFirstRun: Bool
        if hasManagedCreds {
            isFirstRun = false
        } else {
            do {
                isFirstRun = !(try await client.isSetupComplete())
            } catch {
                isFirstRun = false
            }
        }

        if isFirstRun {
            log.info("Auto-connect: fresh install, running setup wizard")
            let wizardOK = await runSetupWizard(client: client)
            isAutoConnecting = false
            if !wizardOK {
                connectionState = .failed("Setup failed — try again")
                setupPhase = nil
            }
            return
        }

        // Step 3: Try saved token
        loadSavedCredentials()
        if let token = authToken {
            log.info("Auto-connect: trying saved token")
            if await verifyToken(client: client, token: token) {
                connectionState = .connected
                isAutoConnecting = false
                log.info("Auto-connect: saved token valid")
                await fetchItemCounts()
                return
            }
            log.info("Auto-connect: saved token expired")
            authToken = nil
        }

        // Step 4: Try saved password
        if let username = UserDefaults.standard.string(forKey: usernameKey),
           let password = UserDefaults.standard.string(forKey: passwordKey) {
            log.info("Auto-connect: re-login with saved credentials")
            do {
                let response = try await client.login(username: username, password: password)
                authToken = response.AccessToken
                connectionState = .connected
                saveCredentials(response.AccessToken, username: username)
                isAutoConnecting = false
                log.info("Auto-connect: re-login succeeded")
                await fetchItemCounts()
                return
            } catch {
                log.warning("Auto-connect: re-login failed: \(error.localizedDescription)")
            }
        }

        // Step 4b: Try managed credentials
        if let mUser = UserDefaults.standard.string(forKey: managedUsernameKey),
           let mPass = UserDefaults.standard.string(forKey: managedPasswordKey) {
            log.info("Auto-connect: trying managed credentials")
            do {
                let response = try await client.login(username: mUser, password: mPass)
                authToken = response.AccessToken
                connectionState = .connected
                saveCredentials(response.AccessToken, username: mUser)
                UserDefaults.standard.set(mPass, forKey: passwordKey)
                isAutoConnecting = false
                log.info("Auto-connect: managed credentials valid")
                await fetchItemCounts()
                return
            } catch {
                log.warning("Auto-connect: managed credentials failed: \(error.localizedDescription)")
            }
        }

        // Step 5: All methods exhausted
        connectionState = .disconnected
        isAutoConnecting = false
        autoConnectExhausted = true
        log.info("Auto-connect: giving up, manual sign-in required")
    }

    private func pollHealth(client: JellyfinAPIClient, maxAttempts: Int, interval: TimeInterval) async -> Bool {
        for attempt in 1...maxAttempts {
            if Task.isCancelled { return false }
            if await client.isHealthy() { return true }
            log.debug("Health poll \(attempt)/\(maxAttempts): not ready")
            try? await Task.sleep(for: .seconds(interval))
        }
        return false
    }

    private func verifyToken(client: JellyfinAPIClient, token: String) async -> Bool {
        do {
            _ = try await client.getItemCounts(token: token)
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
            letters.randomElement()!, upper.randomElement()!,
            digits.randomElement()!, special.randomElement()!,
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
            let response = try await client.login(username: username, password: password)
            authToken = response.AccessToken
            connectionState = .connected
            saveCredentials(response.AccessToken, username: username)
            isManagedByHaven = false
            UserDefaults.standard.removeObject(forKey: passwordKey)
            log.info("Connected to Jellyfin as \(username)")
            await fetchItemCounts()
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
            authToken = response.AccessToken
            connectionState = .connected
            saveCredentials(response.AccessToken, username: username)
            isManagedByHaven = false
            UserDefaults.standard.removeObject(forKey: passwordKey)
            log.info("Connected to Jellyfin as \(username)")
            await fetchItemCounts()
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
        movieCount = nil
        showCount = nil
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
        movieCount = nil
        showCount = nil
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
            apiClient = JellyfinAPIClient(port: p)
        }

        // Reset connection when service stops
        if state != .ready && state != .starting {
            if connectionState != .disconnected {
                autoConnectTask?.cancel()
                autoConnectTask = nil
                isAutoConnecting = false
                autoConnectExhausted = false
                connectionState = .disconnected
                setupPhase = nil
            }
        }

        library = MoviesLibrary(
            libraryPaths: resolvedLibraryPaths,
            scanStatus: currentScanStatus,
            movieCount: movieCount,
            showCount: showCount
        )

        // Auto-connect when service is ready
        if state == .ready && connectionState == .disconnected && !isAutoConnecting && !autoConnectExhausted && setupPhase == nil {
            if isManagedByHaven {
                autoConnectTask?.cancel()
                isAutoConnecting = true
                autoConnectTask = Task { await autoConnect() }
            } else {
                loadSavedCredentials()
                if authToken != nil {
                    connectionState = .connected
                    Task { await fetchItemCounts() }
                }
            }
        }
    }

    // MARK: - Data Fetching

    private func fetchItemCounts() async {
        guard let client = apiClient, let token = authToken else { return }

        for attempt in 1...3 {
            do {
                let counts = try await client.getItemCounts(token: token)
                movieCount = counts.MovieCount
                showCount = counts.SeriesCount
                log.info("Fetched item counts: \(counts.MovieCount) movies, \(counts.SeriesCount) shows")
                updateLibrary()
                return
            } catch {
                let is401 = (error as? JellyfinAPIError).flatMap {
                    if case .httpError(let code, _) = $0, code == 401 { return true }
                    return nil
                } ?? false

                if is401 && attempt < 3 {
                    log.info("Item count fetch got 401, retrying in \(attempt)s (attempt \(attempt)/3)")
                    try? await Task.sleep(for: .seconds(attempt))
                    continue
                }

                log.error("Failed to fetch item counts: \(error.localizedDescription)")
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
        library = MoviesLibrary(
            libraryPaths: resolvedLibraryPaths,
            scanStatus: currentScanStatus,
            movieCount: movieCount,
            showCount: showCount
        )
    }

    // MARK: - Credential Persistence

    private var tokenKey: String { "haven.jellyfin.token.\(capabilityID)" }
    private var usernameKey: String { "haven.jellyfin.username.\(capabilityID)" }
    private var passwordKey: String { "haven.jellyfin.password.\(capabilityID)" }
    private var managedUsernameKey: String { "haven.jellyfin.managedUser.\(capabilityID)" }
    private var managedPasswordKey: String { "haven.jellyfin.managedPass.\(capabilityID)" }
    private var customAccountKey: String { "haven.jellyfin.customAccount.\(capabilityID)" }
    private var libraryPathKey: String { "haven.jellyfin.libraryPath.\(capabilityID)" }
    private var libraryPathsKey: String { "haven.jellyfin.libraryPaths.\(capabilityID)" }

    private var resolvedLibraryPaths: [String] {
        if let saved = UserDefaults.standard.stringArray(forKey: libraryPathsKey), !saved.isEmpty {
            return saved
        }
        // Backward compat: single path from old key or resolvedSettings
        if let single = UserDefaults.standard.string(forKey: libraryPathKey) {
            return [single]
        }
        let stored = serviceManager?.storedState(for: capabilityID)
        if let path = stored?.resolvedSettings["movies_path"] {
            return [path]
        }
        return ["~/Movies"]
    }

    private func saveLibraryPaths(_ paths: [String]) {
        UserDefaults.standard.set(paths, forKey: libraryPathsKey)
        if let first = paths.first {
            UserDefaults.standard.set(first, forKey: libraryPathKey)
            serviceManager?.updateResolvedSetting(for: capabilityID, key: "movies_path", value: first)
        }
        // Unified content_paths key for backup scope (shared convention across all capabilities)
        let joined = paths.joined(separator: ";")
        serviceManager?.updateResolvedSetting(for: capabilityID, key: "content_paths", value: joined)
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
