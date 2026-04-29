import Foundation
import HavenFacade
import HavenCore
import os

private let log = Logger(subsystem: "com.haven", category: "KavitaBooksFacade")

/// Books facade backed by Kavita.
///
/// Auth flow:
/// 1. Service starts → facade polls `/api/health` until Kavita is reachable
/// 2. Tries saved JWT token → if 401, tries saved password → if no password, registers new account
/// 3. If all fail, shows "Sign In" for manual entry
///
/// The `isManagedByHaven` preference (default true) controls whether auto-connect
/// runs automatically. When false, user must sign in manually.
@MainActor
@Observable
package final class KavitaBooksFacade: BooksFacade {
    package let capabilityID: String

    // MARK: - CapabilityFacade

    package private(set) var state: CapabilityState = .idle
    package private(set) var health: CapabilityHealth = .unknown
    package private(set) var advancedURL: URL?

    // MARK: - BooksFacade

    package private(set) var library: BooksLibrary?
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
    package private(set) var itemCount: Int?
    package private(set) var apiKey: String?

    /// Files that Kavita couldn't parse during the last scan.
    package private(set) var scanErrors: [String] = []

    /// True while auto-connect is in progress (health polling + auth).
    package private(set) var isAutoConnecting = false

    /// True after auto-connect tried and exhausted all methods.
    /// Prevents infinite retry loops. Reset on switchToManaged() or manual disconnect/signOut.
    package private(set) var autoConnectExhausted = false

    /// User preference: true = Haven manages the account automatically.
    /// When false, user must sign in manually. Persisted in UserDefaults.
    package var isManagedByHaven: Bool {
        get { !UserDefaults.standard.bool(forKey: customAccountKey) }
        set { UserDefaults.standard.set(!newValue, forKey: customAccountKey) }
    }

    package var connectedUsername: String? {
        guard connectionState == .connected else { return nil }
        return UserDefaults.standard.string(forKey: usernameKey)
    }

    /// True if Haven has a stored password it can use to re-login.
    package var hasSavedCredentials: Bool {
        UserDefaults.standard.string(forKey: passwordKey) != nil
    }

    // MARK: - ConnectableFacade

    package let backendName = "Kavita"

    package var deviceAccessInfo: DeviceAccessInfo? {
        guard let p = port, connectionState == .connected else { return nil }
        let hostname = ProcessInfo.processInfo.hostName
        let address = "http://\(hostname):\(p)"
        let tokenURL: String? = apiKey.map { "http://\(hostname):\(p)/api/opds/\($0)" }
        return DeviceAccessInfo(serverAddress: address, tokenURL: tokenURL)
    }

    // MARK: - Device Access

    /// LAN-accessible server address (e.g. `http://MacBook-Pro.local:5001`).
    package var serverAddress: String? {
        guard let p = port else { return nil }
        let hostname = ProcessInfo.processInfo.hostName
        return "http://\(hostname):\(p)"
    }

    /// OPDS feed URL for e-reader apps (requires connected + apiKey).
    package var opdsURL: String? {
        guard let p = port, let key = apiKey, connectionState == .connected else { return nil }
        let hostname = ProcessInfo.processInfo.hostName
        return "http://\(hostname):\(p)/api/opds/\(key)"
    }

    // MARK: - Internal

    private let lifecycle: FacadeLifecycle
    private weak var serviceManager: ServiceManager?
    private var apiClient: KavitaAPIClient?
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

    // MARK: - BooksFacade Methods

    package func setLibraryPath(_ path: String) async throws {
        try await changeLibraryFolder(to: path)
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

        let expandedPaths = paths.map { ($0 as NSString).expandingTildeInPath } + [expandedPath]

        let libraries = try await client.getLibraries(token: token)
        if let lib = libraries.first {
            try await client.updateLibraryFolders(library: lib, folders: expandedPaths, token: token)
        } else {
            try await client.createLibrary(name: "Books", folders: expandedPaths, token: token)
        }

        paths.append(path)
        saveLibraryPaths(paths)
        log.info("Added library folder: \(path)")

        updateLibrary()

        organizeLibraryFolder(at: expandedPath)
        try await rescan()
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

        let expandedPaths = paths.map { ($0 as NSString).expandingTildeInPath }

        let libraries = try await client.getLibraries(token: token)
        if let lib = libraries.first {
            try await client.updateLibraryFolders(library: lib, folders: expandedPaths, token: token)
        }

        saveLibraryPaths(paths)
        log.info("Removed library folder: \(path)")

        updateLibrary()
        try await rescan()
    }

    /// Change the library folder: update Kavita via API, persist override, rescan.
    package func changeLibraryFolder(to path: String) async throws {
        guard let client = apiClient, let token = authToken else {
            throw FacadeError.adapterError("Not connected")
        }

        let expandedPath = (path as NSString).expandingTildeInPath

        // Create the folder if it doesn't exist
        try FileManager.default.createDirectory(
            atPath: expandedPath,
            withIntermediateDirectories: true
        )

        // Update Kavita library folders via API
        let libraries = try await client.getLibraries(token: token)
        if let lib = libraries.first {
            try await client.updateLibraryFolders(library: lib, folders: [expandedPath], token: token)
        } else {
            try await client.createLibrary(name: "Books", folders: [expandedPath], token: token)
        }

        // Persist the override
        saveLibraryPaths([path])
        log.info("Library folder changed to \(path)")

        updateLibrary()
        try await rescan()
    }

    package func rescan() async throws {
        guard let client = apiClient, let token = authToken else {
            throw FacadeError.adapterError("Not connected")
        }
        guard currentScanStatus != .scanning else { return }
        log.info("Triggering library rescan")
        currentScanStatus = .scanning
        scanErrors = []
        updateLibrary()

        // Organize loose files into subdirectories (Kavita requires this)
        organizeLibraryFolder()

        // Record scan start time for log parsing
        let scanStartTime = Date()

        // Record pre-scan timestamp so we can detect when scan completes
        let libraries = try await client.getLibraries(token: token)
        let preScanTimestamp = libraries.first?.lastScanned

        // Trigger scan
        for lib in libraries {
            log.info("Scanning library \(lib.id): \(lib.name)")
            try await client.scanLibrary(id: lib.id, token: token)
        }

        // Poll for completion: Kavita updates lastScanned when scan finishes
        scanPollTask?.cancel()
        let configDir = serviceManager?.storedState(for: capabilityID)?.directoryLayout.config
        scanPollTask = Task {
            for _ in 1...15 {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                guard let client = self.apiClient, let token = self.authToken else { return }

                if let libs = try? await client.getLibraries(token: token),
                   let lib = libs.first,
                   lib.lastScanned != preScanTimestamp {
                    if let count = try? await client.getSeriesCount(token: token) {
                        self.itemCount = count
                    }
                    log.info("Scan complete (lastScanned changed)")
                    // Parse scan errors from Kavita log
                    if let configDir {
                        self.scanErrors = KavitaLogParser.parseScanErrors(
                            configDir: configDir,
                            after: scanStartTime
                        )
                    }
                    break
                }
            }
            self.currentScanStatus = .idle
            self.setupPhase = nil
            self.updateLibrary()
        }
    }

    // MARK: - Auto-Connect

    /// Waits for Kavita API to be healthy, then authenticates.
    /// Called automatically when service becomes ready and isManagedByHaven is true.
    ///
    /// Two flows:
    /// - **Returning user** (has saved credentials): silent reconnect, no wizard.
    /// - **First run** (no credentials): progressive wizard with account choice + folder picker.
    package func autoConnect() async {
        guard let client = apiClient else { return }
        connectionState = .connecting
        log.info("Auto-connect: waiting for Kavita API...")

        // Step 1: Poll /api/health until reachable
        setupPhase = .waitingForServer
        let healthy = await pollHealth(client: client, maxAttempts: 15, interval: 1.0)
        guard healthy, !Task.isCancelled else {
            if !Task.isCancelled {
                log.warning("Auto-connect: Kavita API not reachable after polling")
                connectionState = .failed("Service is starting — try again in a moment")
            }
            setupPhase = nil
            isAutoConnecting = false
            return
        }
        log.info("Auto-connect: Kavita API is healthy")

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
        // Wizard continues when user calls chooseManaged() or the view opens ConnectSheet
    }

    /// User chose "Set it up for me" during setup wizard.
    package func chooseManaged() {
        guard setupPhase == .awaitingAccountChoice else { return }
        isManagedByHaven = true
        setupPhase = .creatingAccount

        autoConnectTask = Task {
            guard let client = apiClient else { return }

            // Try to register a new managed account
            let username = "haven"
            let password = generatePassword()
            do {
                let response = try await client.register(username: username, password: password)
                authToken = response.token
                apiKey = response.apiKey
                connectionState = .connected
                saveCredentials(response.token, username: username, apiKey: response.apiKey)
                UserDefaults.standard.set(password, forKey: passwordKey)
                UserDefaults.standard.set(username, forKey: managedUsernameKey)
                UserDefaults.standard.set(password, forKey: managedPasswordKey)
                log.info("Setup wizard: registered managed account")
            } catch {
                log.info("Setup wizard: registration failed, trying login: \(error.localizedDescription)")
                // Account may already exist from a previous install — try managed creds
                if let mUser = UserDefaults.standard.string(forKey: managedUsernameKey),
                   let mPass = UserDefaults.standard.string(forKey: managedPasswordKey),
                   let response = try? await client.login(username: mUser, password: mPass) {
                    authToken = response.token
                    apiKey = response.apiKey
                    connectionState = .connected
                    saveCredentials(response.token, username: mUser, apiKey: response.apiKey)
                    log.info("Setup wizard: logged in with existing managed credentials")
                } else {
                    setupPhase = nil
                    connectionState = .failed("Couldn't create account — try signing in manually")
                    return
                }
            }

            // Transition to folder picker
            setupPhase = .awaitingLibraryPath
            log.info("Setup wizard: awaiting library path")
        }
    }

    /// User chose "I have my own account" — open sign-in sheet.
    /// Called from the view; after successful connect(), call continueSetupAfterLogin().
    package func chooseCustom() {
        guard setupPhase == .awaitingAccountChoice else { return }
        isManagedByHaven = false
        // The view will show ConnectSheet; after connect() succeeds,
        // continueSetupAfterLogin() transitions to folder picker.
    }

    /// Called after manual connect() succeeds to continue the setup wizard.
    package func continueSetupAfterLogin() {
        if setupPhase == .awaitingAccountChoice || setupPhase == nil {
            setupPhase = .awaitingLibraryPath
            log.info("Setup wizard: manual login succeeded, awaiting library path")
        }
    }

    /// User confirmed a library folder during setup.
    package func confirmSetupFolder(_ path: String) async throws {
        guard setupPhase == .awaitingLibraryPath else { return }
        setupPhase = .creatingLibrary
        try await changeLibraryFolder(to: path)
        setupPhase = .scanning(progress: nil)
        // Scan polling will clear setupPhase when done
    }

    /// Try all saved credential methods. Returns true if connected.
    private func tryExistingCredentials(client: KavitaAPIClient) async -> Bool {
        loadSavedCredentials()
        if let token = authToken {
            log.info("Auto-connect: trying saved token")
            if await verifyToken(client: client, token: token) {
                connectionState = .connected
                log.info("Auto-connect: saved token valid")
                await fetchLibraryData()
                return true
            }
            authToken = nil
        }

        if let username = UserDefaults.standard.string(forKey: usernameKey),
           let password = UserDefaults.standard.string(forKey: passwordKey) {
            log.info("Auto-connect: re-login with saved credentials")
            if let response = try? await client.login(username: username, password: password) {
                authToken = response.token
                apiKey = response.apiKey
                connectionState = .connected
                saveCredentials(response.token, username: username, apiKey: response.apiKey)
                log.info("Auto-connect: re-login succeeded")
                await fetchLibraryData()
                return true
            }
        }

        if let mUser = UserDefaults.standard.string(forKey: managedUsernameKey),
           let mPass = UserDefaults.standard.string(forKey: managedPasswordKey) {
            log.info("Auto-connect: trying managed credentials")
            if let response = try? await client.login(username: mUser, password: mPass) {
                authToken = response.token
                apiKey = response.apiKey
                connectionState = .connected
                saveCredentials(response.token, username: mUser, apiKey: response.apiKey)
                UserDefaults.standard.set(mPass, forKey: passwordKey)
                log.info("Auto-connect: managed credentials valid")
                await fetchLibraryData()
                return true
            }
        }

        return false
    }

    /// Poll `/api/health` until it returns 200.
    private func pollHealth(client: KavitaAPIClient, maxAttempts: Int, interval: TimeInterval) async -> Bool {
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

    /// Verify a JWT token is still valid by making a lightweight API call.
    private func verifyToken(client: KavitaAPIClient, token: String) async -> Bool {
        do {
            _ = try await client.getLibraries(token: token)
            return true
        } catch {
            return false
        }
    }

    /// Generate a strong random password for auto-provisioned accounts.
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

    /// Create the initial admin account on a fresh Kavita install, then connect.
    package func createAccount(username: String, password: String) async throws {
        guard let client = apiClient else {
            throw FacadeError.adapterError("Service is not running")
        }

        connectionState = .connecting
        do {
            let response = try await client.register(username: username, password: password)
            authToken = response.token
            apiKey = response.apiKey
            connectionState = .connected
            saveCredentials(response.token, username: username, apiKey: response.apiKey)
            log.info("Created Kavita admin account: \(username)")
            await fetchLibraryData()
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
            let loginResponse = try await client.login(username: username, password: password)
            authToken = loginResponse.token
            apiKey = loginResponse.apiKey
            connectionState = .connected
            saveCredentials(loginResponse.token, username: username, apiKey: loginResponse.apiKey)
            // Custom account: clear Haven password, mark as not managed
            isManagedByHaven = false
            UserDefaults.standard.removeObject(forKey: passwordKey)
            log.info("Connected to Kavita as \(username)")
            await fetchLibraryData()
        } catch {
            connectionState = .failed(error.localizedDescription)
            authToken = nil
            throw error
        }
    }

    /// Disconnect from Kavita. Preserves Haven password for potential reconnect.
    package func disconnect() {
        autoConnectTask?.cancel()
        autoConnectTask = nil
        scanPollTask?.cancel()
        scanPollTask = nil
        isAutoConnecting = false
        authToken = nil
        apiKey = nil
        connectionState = .disconnected
        itemCount = nil
        currentScanStatus = .idle
        setupPhase = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        updateLibrary()
    }

    /// Fully sign out and clear all stored credentials.
    package func signOut() {
        autoConnectTask?.cancel()
        autoConnectTask = nil
        scanPollTask?.cancel()
        scanPollTask = nil
        isAutoConnecting = false
        authToken = nil
        apiKey = nil
        connectionState = .disconnected
        itemCount = nil
        currentScanStatus = .idle
        setupPhase = nil
        clearAllCredentials()
        updateLibrary()
    }

    /// Switch to managed mode: disconnect custom session, auto-connect with managed credentials.
    package func switchToManaged() {
        isManagedByHaven = true
        autoConnectExhausted = false
        disconnect()  // Clears token but preserves managed credentials
        if state == .ready {
            autoConnectTask = Task { await autoConnect() }
        }
    }

    /// Switch to custom account mode: disconnect and let user sign in.
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
            apiClient = KavitaAPIClient(port: p)
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

        library = BooksLibrary(
            libraryPaths: resolvedLibraryPaths,
            scanStatus: currentScanStatus,
            itemCount: itemCount
        )

        // Auto-connect when service is ready
        if state == .ready && connectionState == .disconnected && !isAutoConnecting && !autoConnectExhausted {
            if isManagedByHaven {
                autoConnectTask?.cancel()
                isAutoConnecting = true
                autoConnectTask = Task { await autoConnect() }
            } else {
                // Custom mode: just try saved token (no password/register)
                loadSavedCredentials()
                if authToken != nil {
                    connectionState = .connected
                    Task { await fetchLibraryData() }
                }
            }
        }
    }

    // MARK: - Data Fetching

    private func fetchLibraryData() async {
        guard let client = apiClient, let token = authToken else { return }

        do {
            var libraries = try await client.getLibraries(token: token)

            // Auto-create library if none exists (first-time setup)
            if libraries.isEmpty {
                let expandedPath = (resolvedLibraryPath as NSString).expandingTildeInPath
                log.info("No Kavita libraries found — creating 'Books' library at \(expandedPath)")
                try await client.createLibrary(name: "Books", folders: [expandedPath], token: token)
                // Organize loose files, re-fetch, and trigger initial scan
                organizeLibraryFolder()
                libraries = try await client.getLibraries(token: token)
                for lib in libraries {
                    try? await client.scanLibrary(id: lib.id, token: token)
                }
            }

            // Auto-fix libraries with unsafe fileGroupTypes (0, 1, 5 crash macOS scanner)
            let safeTypes = [2, 3, 4]
            for lib in libraries {
                if let types = lib.libraryFileTypes, types != safeTypes {
                    log.info("Fixing library \(lib.id) fileTypes from \(types) to \(safeTypes)")
                    try? await client.updateLibraryFileTypes(library: lib, fileTypes: safeTypes, token: token)
                }
            }

            let count = try await client.getSeriesCount(token: token)
            itemCount = count
            log.info("Fetched library data: \(libraries.count) libraries, \(count) series")
            updateLibrary()

            // Auto-rescan on connect: organize loose files and pick up changes since last run
            if currentScanStatus != .scanning {
                try? await rescan()
            }
        } catch {
            log.error("Failed to fetch library data: \(error.localizedDescription)")
            if let apiError = error as? KavitaAPIError,
               case .httpError(let code, _) = apiError, code == 401 {
                connectionState = .failed("Session expired — reconnect")
                authToken = nil
                clearAllCredentials()
            }
        }
    }

    private func updateLibrary() {
        library = BooksLibrary(
            libraryPaths: resolvedLibraryPaths,
            scanStatus: currentScanStatus,
            itemCount: itemCount
        )
    }

    // MARK: - Library Organization

    private func organizeLibraryFolder() {
        for path in resolvedLibraryPaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            LibraryOrganizer.organize(at: URL(fileURLWithPath: expandedPath))
        }
    }

    private func organizeLibraryFolder(at expandedPath: String) {
        LibraryOrganizer.organize(at: URL(fileURLWithPath: expandedPath))
    }

    // MARK: - Token Persistence

    private var tokenKey: String { "haven.kavita.token.\(capabilityID)" }
    private var usernameKey: String { "haven.kavita.username.\(capabilityID)" }
    private var passwordKey: String { "haven.kavita.password.\(capabilityID)" }
    private var managedUsernameKey: String { "haven.kavita.managedUser.\(capabilityID)" }
    private var managedPasswordKey: String { "haven.kavita.managedPass.\(capabilityID)" }
    private var apiKeyKey: String { "haven.kavita.apiKey.\(capabilityID)" }
    private var customAccountKey: String { "haven.kavita.customAccount.\(capabilityID)" }
    private var libraryPathOverrideKey: String { "haven.kavita.libraryPath.\(capabilityID)" }
    private var libraryPathsKey: String { "haven.kavita.libraryPaths.\(capabilityID)" }

    private func saveCredentials(_ token: String, username: String, apiKey: String?) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        UserDefaults.standard.set(username, forKey: usernameKey)
        if let apiKey { UserDefaults.standard.set(apiKey, forKey: apiKeyKey) }
    }

    private func loadSavedCredentials() {
        authToken = UserDefaults.standard.string(forKey: tokenKey)
        apiKey = UserDefaults.standard.string(forKey: apiKeyKey)
    }

    /// All resolved library paths: multi-path key > single-path override > stored settings > default.
    private var resolvedLibraryPaths: [String] {
        if let saved = UserDefaults.standard.stringArray(forKey: libraryPathsKey), !saved.isEmpty {
            return saved
        }
        // Backward compat: single path from old key or resolvedSettings
        if let override = UserDefaults.standard.string(forKey: libraryPathOverrideKey) {
            return [override]
        }
        let stored = serviceManager?.storedState(for: capabilityID)
        if let path = stored?.resolvedSettings["library_path"] {
            return [path]
        }
        return ["~/Books"]
    }

    /// Primary resolved library path (first one).
    private var resolvedLibraryPath: String {
        resolvedLibraryPaths.first ?? "~/Books"
    }

    private func saveLibraryPaths(_ paths: [String]) {
        UserDefaults.standard.set(paths, forKey: libraryPathsKey)
        if let first = paths.first {
            UserDefaults.standard.set(first, forKey: libraryPathOverrideKey)
            serviceManager?.updateResolvedSetting(for: capabilityID, key: "library_path", value: first)
        }
        // Unified content_paths key for backup scope (shared convention across all capabilities)
        let joined = paths.joined(separator: ";")
        serviceManager?.updateResolvedSetting(for: capabilityID, key: "content_paths", value: joined)
    }

    private func clearAllCredentials() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: passwordKey)
        UserDefaults.standard.removeObject(forKey: managedUsernameKey)
        UserDefaults.standard.removeObject(forKey: managedPasswordKey)
        UserDefaults.standard.removeObject(forKey: apiKeyKey)
        UserDefaults.standard.removeObject(forKey: customAccountKey)
        UserDefaults.standard.removeObject(forKey: libraryPathOverrideKey)
        UserDefaults.standard.removeObject(forKey: libraryPathsKey)
    }
}

// MARK: - Library Organizer

/// Moves loose book files in a directory into subdirectories.
///
/// Kavita requires books to be inside subdirectories (e.g. `Books/Title/file.epub`).
/// Users naturally drop files directly into the library folder, so we organize them
/// transparently before each scan.
package enum LibraryOrganizer {
    package static let bookExtensions: Set<String> = [
        "epub", "pdf", "cbz", "cbr", "cb7", "cbt", "zip", "rar", "7z"
    ]

    package static func organize(at libraryURL: URL) {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for fileURL in contents {
            let ext = fileURL.pathExtension.lowercased()
            guard bookExtensions.contains(ext) else { continue }

            let title = fileURL.deletingPathExtension().lastPathComponent
            let subdir = libraryURL.appendingPathComponent(title)
            let destination = subdir.appendingPathComponent(fileURL.lastPathComponent)

            do {
                if !fm.fileExists(atPath: subdir.path) {
                    try fm.createDirectory(at: subdir, withIntermediateDirectories: true)
                }
                try fm.moveItem(at: fileURL, to: destination)
                log.info("Organized: \(fileURL.lastPathComponent) → \(title)/")
            } catch {
                log.warning("Failed to organize \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Kavita Log Parser

/// Parses Kavita log files to extract scan errors (files that couldn't be processed).
enum KavitaLogParser {
    /// Parse scan errors from the most recent Kavita log file.
    /// Returns deduplicated file names (not full paths) of files that failed to parse.
    static func parseScanErrors(configDir: URL, after startTime: Date) -> [String] {
        let timestampRegex = /\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})/
        let parseErrorRegex = /Unable to parse any meaningful information out of file (.+)$/
        let logsDir = configDir.appendingPathComponent("logs")
        let fm = FileManager.default

        // Find the most recent kavita log file
        guard let logFiles = try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil),
              let latestLog = logFiles
                .filter({ $0.lastPathComponent.hasPrefix("kavita") && $0.pathExtension == "log" })
                .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
                .first,
              let content = try? String(contentsOf: latestLog, encoding: .utf8)
        else { return [] }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        // Kavita logs include timezone offset but we compare loosely — just use local time
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var errorFiles: Set<String> = []

        for line in content.split(separator: "\n").reversed() {
            let lineStr = String(line)

            // Only look at [Error] lines
            guard lineStr.contains("[Error]") else { continue }

            // Parse timestamp — skip lines before scan start
            if let match = lineStr.firstMatch(of: timestampRegex) {
                let tsString = String(match.1)
                if let ts = dateFormatter.date(from: tsString), ts < startTime {
                    break // Logs are chronological, so we can stop once we pass the start time
                }
            }

            // Extract failed file path
            if let match = lineStr.firstMatch(of: parseErrorRegex) {
                let fullPath = String(match.1)
                let fileName = (fullPath as NSString).lastPathComponent
                errorFiles.insert(fileName)
            }
        }

        return errorFiles.sorted()
    }
}

