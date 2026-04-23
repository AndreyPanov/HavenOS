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

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected, connecting, connected, failed(String)
    }

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var itemCount: Int?
    private(set) var apiKey: String?

    /// Files that Kavita couldn't parse during the last scan.
    private(set) var scanErrors: [String] = []

    /// True while auto-connect is in progress (health polling + auth).
    private(set) var isAutoConnecting = false

    /// True after auto-connect tried and exhausted all methods.
    /// Prevents infinite retry loops. Reset on switchToManaged() or manual disconnect/signOut.
    private var autoConnectExhausted = false

    /// User preference: true = Haven manages the account automatically.
    /// When false, user must sign in manually. Persisted in UserDefaults.
    var isManagedByHaven: Bool {
        get { !UserDefaults.standard.bool(forKey: customAccountKey) }
        set { UserDefaults.standard.set(!newValue, forKey: customAccountKey) }
    }

    var connectedUsername: String? {
        guard connectionState == .connected else { return nil }
        return UserDefaults.standard.string(forKey: usernameKey)
    }

    /// True if Haven has a stored password it can use to re-login.
    var hasSavedCredentials: Bool {
        UserDefaults.standard.string(forKey: passwordKey) != nil
    }

    // MARK: - Device Access

    /// LAN-accessible server address (e.g. `http://MacBook-Pro.local:5001`).
    var serverAddress: String? {
        guard let p = port else { return nil }
        let hostname = ProcessInfo.processInfo.hostName
        return "http://\(hostname):\(p)"
    }

    /// OPDS feed URL for e-reader apps (requires connected + apiKey).
    var opdsURL: String? {
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

    // MARK: - BooksFacade Methods

    func setLibraryPath(_ path: String) async throws {
        try await changeLibraryFolder(to: path)
    }

    /// Change the library folder: update Kavita via API, persist override, rescan.
    func changeLibraryFolder(to path: String) async throws {
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

        // Persist the override in UserDefaults
        UserDefaults.standard.set(path, forKey: libraryPathOverrideKey)
        log.info("Library folder changed to \(path)")

        updateLibrary()
        try await rescan()
    }

    func rescan() async throws {
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
            self.updateLibrary()
        }
    }

    // MARK: - Auto-Connect

    /// Waits for Kavita API to be healthy, then authenticates.
    /// Called automatically when service becomes ready and isManagedByHaven is true.
    func autoConnect() async {
        guard let client = apiClient else { return }
        guard !isAutoConnecting else { return }

        isAutoConnecting = true
        connectionState = .connecting
        log.info("Auto-connect: waiting for Kavita API...")

        // Step 1: Poll /api/health until reachable (max 15 seconds)
        let healthy = await pollHealth(client: client, maxAttempts: 15, interval: 1.0)
        guard healthy else {
            log.warning("Auto-connect: Kavita API not reachable after polling")
            connectionState = .failed("Service is starting — try again in a moment")
            isAutoConnecting = false
            return
        }
        log.info("Auto-connect: Kavita API is healthy")

        // Step 2: Try saved JWT token
        loadSavedCredentials()
        if let token = authToken {
            log.info("Auto-connect: trying saved token")
            if await verifyToken(client: client, token: token) {
                connectionState = .connected
                log.info("Auto-connect: saved token valid")
                await fetchLibraryData()
                isAutoConnecting = false
                return
            }
            log.info("Auto-connect: saved token expired")
            authToken = nil
        }

        // Step 3: Try saved password (Haven-managed account)
        if let username = UserDefaults.standard.string(forKey: usernameKey),
           let password = UserDefaults.standard.string(forKey: passwordKey) {
            log.info("Auto-connect: re-login with saved credentials")
            do {
                let response = try await client.login(username: username, password: password)
                authToken = response.token
                apiKey = response.apiKey
                connectionState = .connected
                saveCredentials(response.token, username: username, apiKey: response.apiKey)
                log.info("Auto-connect: re-login succeeded")
                await fetchLibraryData()
                isAutoConnecting = false
                return
            } catch {
                log.warning("Auto-connect: re-login failed: \(error.localizedDescription)")
            }
        }

        // Step 3b: Try managed credentials (Haven-provisioned account, survives custom sign-in)
        if let mUser = UserDefaults.standard.string(forKey: managedUsernameKey),
           let mPass = UserDefaults.standard.string(forKey: managedPasswordKey) {
            log.info("Auto-connect: trying managed credentials")
            do {
                let response = try await client.login(username: mUser, password: mPass)
                authToken = response.token
                apiKey = response.apiKey
                connectionState = .connected
                saveCredentials(response.token, username: mUser, apiKey: response.apiKey)
                UserDefaults.standard.set(mPass, forKey: passwordKey)
                log.info("Auto-connect: managed credentials valid")
                await fetchLibraryData()
                isAutoConnecting = false
                return
            } catch {
                log.warning("Auto-connect: managed credentials failed: \(error.localizedDescription)")
            }
        }

        // Step 4: Try to register a new account (fresh Kavita install)
        log.info("Auto-connect: attempting registration")
        let username = "haven"
        let password = generatePassword()
        do {
            let response = try await client.register(username: username, password: password)
            authToken = response.token
            apiKey = response.apiKey
            connectionState = .connected
            saveCredentials(response.token, username: username, apiKey: response.apiKey)
            UserDefaults.standard.set(password, forKey: passwordKey)
            // Persist managed credentials separately so they survive custom sign-in
            UserDefaults.standard.set(username, forKey: managedUsernameKey)
            UserDefaults.standard.set(password, forKey: managedPasswordKey)
            log.info("Auto-connect: registered new account")
            await fetchLibraryData()
            isAutoConnecting = false
            return
        } catch {
            log.info("Auto-connect: registration failed (account exists?): \(error.localizedDescription)")
        }

        // Step 5: All methods exhausted — user must sign in manually
        connectionState = .disconnected
        isAutoConnecting = false
        autoConnectExhausted = true
        log.info("Auto-connect: giving up, manual sign-in required")
    }

    /// Poll `/api/health` until it returns 200.
    private func pollHealth(client: KavitaAPIClient, maxAttempts: Int, interval: TimeInterval) async -> Bool {
        for attempt in 1...maxAttempts {
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
    func createAccount(username: String, password: String) async throws {
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

    func connect(username: String, password: String) async throws {
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
    func disconnect() {
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
        UserDefaults.standard.removeObject(forKey: tokenKey)
        updateLibrary()
    }

    /// Fully sign out and clear all stored credentials.
    func signOut() {
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
        clearAllCredentials()
        updateLibrary()
    }

    /// Switch to managed mode: disconnect custom session, auto-connect with managed credentials.
    func switchToManaged() {
        isManagedByHaven = true
        autoConnectExhausted = false
        disconnect()  // Clears token but preserves managed credentials
        if state == .ready {
            autoConnectTask = Task { await autoConnect() }
        }
    }

    /// Switch to custom account mode: disconnect and let user sign in.
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
            libraryPath: resolvedLibraryPath,
            scanStatus: currentScanStatus,
            itemCount: itemCount
        )

        // Auto-connect when service is ready
        if state == .ready && connectionState == .disconnected && !isAutoConnecting && !autoConnectExhausted {
            if isManagedByHaven {
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
            libraryPath: resolvedLibraryPath,
            scanStatus: currentScanStatus,
            itemCount: itemCount
        )
    }

    // MARK: - Library Organization

    private func organizeLibraryFolder() {
        let expandedPath = (resolvedLibraryPath as NSString).expandingTildeInPath
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

    private func saveCredentials(_ token: String, username: String, apiKey: String?) {
        UserDefaults.standard.set(token, forKey: tokenKey)
        UserDefaults.standard.set(username, forKey: usernameKey)
        if let apiKey { UserDefaults.standard.set(apiKey, forKey: apiKeyKey) }
    }

    private func loadSavedCredentials() {
        authToken = UserDefaults.standard.string(forKey: tokenKey)
        apiKey = UserDefaults.standard.string(forKey: apiKeyKey)
    }

    /// Resolved library path: UserDefaults override > stored settings > default.
    private var resolvedLibraryPath: String {
        if let override = UserDefaults.standard.string(forKey: libraryPathOverrideKey) {
            return override
        }
        let stored = serviceManager?.storedState(for: capabilityID)
        return stored?.resolvedSettings["library_path"] ?? "~/Books"
    }

    private func clearAllCredentials() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: passwordKey)
        UserDefaults.standard.removeObject(forKey: managedUsernameKey)
        UserDefaults.standard.removeObject(forKey: managedPasswordKey)
        UserDefaults.standard.removeObject(forKey: apiKeyKey)
        UserDefaults.standard.removeObject(forKey: customAccountKey)
    }
}

// MARK: - Library Organizer

/// Moves loose book files in a directory into subdirectories.
///
/// Kavita requires books to be inside subdirectories (e.g. `Books/Title/file.epub`).
/// Users naturally drop files directly into the library folder, so we organize them
/// transparently before each scan.
enum LibraryOrganizer {
    static let bookExtensions: Set<String> = [
        "epub", "pdf", "cbz", "cbr", "cb7", "cbt", "zip", "rar", "7z"
    ]

    static func organize(at libraryURL: URL) {
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

