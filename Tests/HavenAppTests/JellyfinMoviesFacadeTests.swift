import Testing
import Foundation
import HavenFacade
import HavenAppKit

// MARK: - Auth State Machine Tests

@Suite("JellyfinMoviesFacade Auth State Machine")
struct JellyfinMoviesFacadeTests {

    private func makeTestID() -> String {
        "haven.test.jellyfin.\(UUID().uuidString)"
    }

    private func cleanupDefaults(for id: String) {
        for key in [
            "haven.jellyfin.token.\(id)",
            "haven.jellyfin.username.\(id)",
            "haven.jellyfin.password.\(id)",
            "haven.jellyfin.managedUser.\(id)",
            "haven.jellyfin.managedPass.\(id)",
            "haven.jellyfin.customAccount.\(id)",
            "haven.jellyfin.libraryPath.\(id)",
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @MainActor
    private func makeFacade() -> (JellyfinMoviesFacade, String) {
        let id = makeTestID()
        let sm = ServiceManager()
        return (JellyfinMoviesFacade(capabilityID: id, serviceManager: sm), id)
    }

    // MARK: - Fresh Install

    @Test("Fresh facade: disconnected, managed=true, no credentials")
    @MainActor func freshInstall() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        #expect(f.connectionState == .disconnected)
        #expect(f.isManagedByHaven == true)
        #expect(f.connectedUsername == nil)
        #expect(f.isAutoConnecting == false)
        #expect(f.autoConnectExhausted == false)
        #expect(f.state == .idle)
        #expect(f.setupPhase == nil)
        #expect(f.library == nil)
    }

    // MARK: - setupState Derivation

    @Test("setupState: disconnected maps to needsSetup")
    @MainActor func setupStateDisconnected() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        #expect(f.setupState == .needsSetup(message: "Connect to see your library"))
    }

    // MARK: - isManagedByHaven

    @Test("isManagedByHaven persists in UserDefaults")
    @MainActor func managedPersistence() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.isManagedByHaven = false
        #expect(f.isManagedByHaven == false)
        #expect(UserDefaults.standard.bool(forKey: "haven.jellyfin.customAccount.\(id)") == true)

        f.isManagedByHaven = true
        #expect(f.isManagedByHaven == true)
    }

    @Test("isManagedByHaven persists across facade instances")
    @MainActor func managedPersistsAcrossInstances() async {
        let id = makeTestID()
        defer { cleanupDefaults(for: id) }

        let sm = ServiceManager()
        let f1 = JellyfinMoviesFacade(capabilityID: id, serviceManager: sm)
        f1.isManagedByHaven = false

        let f2 = JellyfinMoviesFacade(capabilityID: id, serviceManager: sm)
        #expect(f2.isManagedByHaven == false)
    }

    // MARK: - disconnect()

    @Test("disconnect: clears token, sets disconnected, clears stats")
    @MainActor func disconnectClearsState() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        UserDefaults.standard.set("pw", forKey: "haven.jellyfin.password.\(id)")
        UserDefaults.standard.set("tk", forKey: "haven.jellyfin.token.\(id)")
        UserDefaults.standard.set("user", forKey: "haven.jellyfin.username.\(id)")

        f.disconnect()

        #expect(f.connectionState == .disconnected)
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.token.\(id)") == nil)
        #expect(f.connectedUsername == nil)
        #expect(f.setupPhase == nil)
    }

    @Test("disconnect: multiple calls are safe")
    @MainActor func disconnectIdempotent() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.disconnect()
        f.disconnect()
        f.disconnect()
        #expect(f.connectionState == .disconnected)
    }

    // MARK: - signOut()

    @Test("signOut: clears all stored credentials")
    @MainActor func signOutClearsAll() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        UserDefaults.standard.set("pw", forKey: "haven.jellyfin.password.\(id)")
        UserDefaults.standard.set("tk", forKey: "haven.jellyfin.token.\(id)")
        UserDefaults.standard.set("user", forKey: "haven.jellyfin.username.\(id)")
        UserDefaults.standard.set("mu", forKey: "haven.jellyfin.managedUser.\(id)")
        UserDefaults.standard.set("mp", forKey: "haven.jellyfin.managedPass.\(id)")
        UserDefaults.standard.set("/some/path", forKey: "haven.jellyfin.libraryPath.\(id)")

        f.signOut()

        #expect(f.connectionState == .disconnected)
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.token.\(id)") == nil)
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.username.\(id)") == nil)
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.password.\(id)") == nil)
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.managedUser.\(id)") == nil)
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.managedPass.\(id)") == nil)
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.libraryPath.\(id)") == nil)
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.customAccount.\(id)") == nil)
    }

    @Test("signOut after disconnect: still clears password and managed creds")
    @MainActor func signOutAfterDisconnect() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        UserDefaults.standard.set("pw", forKey: "haven.jellyfin.password.\(id)")
        UserDefaults.standard.set("tk", forKey: "haven.jellyfin.token.\(id)")

        f.disconnect()
        // Token cleared by disconnect
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.token.\(id)") == nil)
        // Password still there after disconnect
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.password.\(id)") == "pw")

        f.signOut()
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.password.\(id)") == nil)
    }

    // MARK: - switchToManaged / switchToCustom

    @Test("switchToCustom: sets flag and disconnects")
    @MainActor func switchToCustom() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.switchToCustom()
        #expect(f.isManagedByHaven == false)
        #expect(f.connectionState == .disconnected)
    }

    @Test("switchToManaged: sets flag, resets exhausted, disconnects")
    @MainActor func switchToManaged() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.isManagedByHaven = false
        UserDefaults.standard.set("tk", forKey: "haven.jellyfin.token.\(id)")

        f.switchToManaged()
        #expect(f.isManagedByHaven == true)
        #expect(f.autoConnectExhausted == false)
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.token.\(id)") == nil)
    }

    // MARK: - autoConnect() Without API

    @Test("autoConnect: no-op when apiClient is nil")
    @MainActor func autoConnectNoClient() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        await f.autoConnect()
        #expect(f.connectionState == .disconnected)
        #expect(f.isAutoConnecting == false)
    }

    // MARK: - Available Actions

    @Test("Idle: start and remove available")
    @MainActor func actionsIdle() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        #expect(f.state == .idle)
        let ids = f.availableActions.map(\.id)
        #expect(ids.contains(CapabilityAction.start.id))
        #expect(ids.contains(CapabilityAction.remove.id))
        #expect(!ids.contains(CapabilityAction.stop.id))
        #expect(!ids.contains(CapabilityAction.rescan.id))
    }

    // MARK: - connectedUsername

    @Test("connectedUsername: nil when disconnected, even with saved username")
    @MainActor func usernameRequiresConnection() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        UserDefaults.standard.set("haven", forKey: "haven.jellyfin.username.\(id)")
        #expect(f.connectionState == .disconnected)
        #expect(f.connectedUsername == nil)
    }

    // MARK: - Library Updates

    @Test("disconnect clears library stats (movieCount/showCount)")
    @MainActor func disconnectClearsStats() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.disconnect()
        // After disconnect, library should reflect nil counts
        if let lib = f.library {
            #expect(lib.movieCount == nil)
            #expect(lib.showCount == nil)
        }
    }

    @Test("library is nil when service not installed")
    @MainActor func libraryNilWhenIdle() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        #expect(f.state == .idle)
        #expect(f.library == nil)
    }

    // MARK: - Settings Toggle Flow

    @Test("Toggle OFF: disconnect, show Sign In needed")
    @MainActor func settingsToggleOff() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        UserDefaults.standard.set("pw", forKey: "haven.jellyfin.password.\(id)")
        UserDefaults.standard.set("tk", forKey: "haven.jellyfin.token.\(id)")

        f.switchToCustom()

        #expect(f.isManagedByHaven == false)
        #expect(f.connectionState == .disconnected)
        #expect(f.setupState == .needsSetup(message: "Connect to see your library"))
    }

    @Test("Toggle OFF then ON: restores managed")
    @MainActor func settingsToggleOffOn() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.switchToCustom()
        #expect(f.isManagedByHaven == false)

        f.switchToManaged()
        #expect(f.isManagedByHaven == true)
    }

    // MARK: - Setup Phase

    @Test("setupPhase starts nil on fresh facade")
    @MainActor func setupPhaseStartsNil() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        #expect(f.setupPhase == nil)
    }

    @Test("disconnect clears setupPhase")
    @MainActor func disconnectClearsSetupPhase() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.disconnect()
        #expect(f.setupPhase == nil)
    }

    @Test("signOut clears setupPhase")
    @MainActor func signOutClearsSetupPhase() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.signOut()
        #expect(f.setupPhase == nil)
    }

    // MARK: - Library Path Persistence

    @Test("Library path saved to UserDefaults key")
    @MainActor func libraryPathPersistence() async {
        let id = makeTestID()
        defer { cleanupDefaults(for: id) }

        let key = "haven.jellyfin.libraryPath.\(id)"
        UserDefaults.standard.set("/Volumes/Media/Movies", forKey: key)

        let stored = UserDefaults.standard.string(forKey: key)
        #expect(stored == "/Volumes/Media/Movies")
    }

    @Test("signOut clears library path")
    @MainActor func signOutClearsLibraryPath() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        UserDefaults.standard.set("/some/path", forKey: "haven.jellyfin.libraryPath.\(id)")
        f.signOut()
        #expect(UserDefaults.standard.string(forKey: "haven.jellyfin.libraryPath.\(id)") == nil)
    }

    // MARK: - rescan Guards

    @Test("rescan throws when not connected")
    @MainActor func rescanThrowsWhenDisconnected() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        do {
            try await f.rescan()
            Issue.record("Expected error")
        } catch {
            #expect(error is FacadeError)
        }
    }

    // MARK: - setLibraryPath Guards

    @Test("setLibraryPath throws when not connected")
    @MainActor func setLibraryPathThrowsWhenDisconnected() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        do {
            try await f.setLibraryPath("/Movies", contentType: .moviesAndShows)
            Issue.record("Expected error")
        } catch {
            #expect(error is FacadeError)
        }
    }

    // MARK: - deviceAccessInfo

    @Test("deviceAccessInfo nil when not connected")
    @MainActor func deviceAccessInfoNilWhenDisconnected() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        #expect(f.deviceAccessInfo == nil)
    }
}

// MARK: - SetupPhase Tests

@Suite("SetupPhase Enum")
struct SetupPhaseTests {

    @Test("All phases are distinct")
    func phasesDistinct() {
        let phases: [SetupPhase] = [
            .waitingForServer,
            .creatingAccount,
            .awaitingLibraryPath,
            .awaitingLibraryType,
            .creatingLibrary,
            .scanning(progress: nil),
            .scanning(progress: 50.0),
            .complete,
        ]

        for (i, a) in phases.enumerated() {
            for (j, b) in phases.enumerated() {
                if i != j { #expect(a != b, "Phase \(i) should differ from \(j)") }
            }
        }
    }

    @Test("Scanning with progress is equatable")
    func scanningEquality() {
        #expect(SetupPhase.scanning(progress: 50.0) == SetupPhase.scanning(progress: 50.0))
        #expect(SetupPhase.scanning(progress: nil) == SetupPhase.scanning(progress: nil))
        #expect(SetupPhase.scanning(progress: 50.0) != SetupPhase.scanning(progress: 75.0))
    }
}

// MARK: - LibraryContentType Tests

@Suite("LibraryContentType")
struct LibraryContentTypeTests {

    @Test("All cases have labels")
    func allCasesLabeled() {
        for ct in LibraryContentType.allCases {
            #expect(!ct.label.isEmpty)
        }
    }

    @Test("Raw values are distinct")
    func rawValuesDistinct() {
        let raws = LibraryContentType.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
    }

    @Test("moviesAndShows is mixed")
    func mixedRawValue() {
        #expect(LibraryContentType.moviesAndShows.rawValue == "mixed")
    }
}

// MARK: - MoviesLibrary Value Type Tests

@Suite("MoviesLibrary Value Type")
struct MoviesLibraryTests {

    @Test("Default init has idle scan and nil counts")
    func defaultInit() {
        let lib = MoviesLibrary(libraryPath: "/Movies")
        #expect(lib.libraryPath == "/Movies")
        #expect(lib.scanStatus == .idle)
        #expect(lib.movieCount == nil)
        #expect(lib.showCount == nil)
    }

    @Test("Equatable: identical libraries are equal")
    func equatable() {
        let a = MoviesLibrary(libraryPath: "/Movies", movieCount: 5, showCount: 2)
        let b = MoviesLibrary(libraryPath: "/Movies", movieCount: 5, showCount: 2)
        #expect(a == b)
    }

    @Test("Equatable: different counts are not equal")
    func notEquatable() {
        let a = MoviesLibrary(libraryPath: "/Movies", movieCount: 5)
        let b = MoviesLibrary(libraryPath: "/Movies", movieCount: 10)
        #expect(a != b)
    }
}

// MARK: - API Error Parsing Tests

@Suite("JellyfinAPIError Message Extraction")
struct JellyfinAPIErrorTests {

    @Test("401 empty body → Invalid credentials")
    func unauthorized() {
        let e = JellyfinAPIError.httpError(statusCode: 401, body: "")
        #expect(e.localizedDescription == "Invalid credentials")
    }

    @Test("Object message field")
    func messageField() {
        let e = JellyfinAPIError.httpError(statusCode: 403, body: "{\"message\":\"Forbidden\"}")
        #expect(e.localizedDescription == "Forbidden")
    }

    @Test("Object Message field (capitalized)")
    func capitalizedMessageField() {
        let e = JellyfinAPIError.httpError(statusCode: 403, body: "{\"Message\":\"Access denied\"}")
        #expect(e.localizedDescription == "Access denied")
    }

    @Test("Object error field")
    func errorField() {
        let e = JellyfinAPIError.httpError(statusCode: 500, body: "{\"error\":\"Internal\"}")
        #expect(e.localizedDescription == "Internal")
    }

    @Test("Object detail field")
    func detailField() {
        let e = JellyfinAPIError.httpError(statusCode: 429, body: "{\"detail\":\"Rate limit\"}")
        #expect(e.localizedDescription == "Rate limit")
    }

    @Test("Raw text fallback")
    func rawText() {
        let e = JellyfinAPIError.httpError(statusCode: 500, body: "Oops")
        #expect(e.localizedDescription == "Oops")
    }

    @Test("Empty body fallback shows status code")
    func emptyBody() {
        let e = JellyfinAPIError.httpError(statusCode: 503, body: "")
        #expect(e.localizedDescription == "Server error (503)")
    }

    @Test("401 with message overrides default")
    func unauthorizedMsg() {
        let e = JellyfinAPIError.httpError(statusCode: 401, body: "{\"message\":\"Locked\"}")
        #expect(e.localizedDescription == "Locked")
    }
}

// MARK: - API Client Unit Tests

@Suite("JellyfinAPIClient Request Building")
struct JellyfinAPIClientTests {

    @Test("Client initializes with correct base URL")
    func initBaseURL() {
        let client = JellyfinAPIClient(port: 8096)
        #expect(client.baseURL.absoluteString == "http://localhost:8096")
    }

    @Test("Client uses different ports")
    func initDifferentPort() {
        let client = JellyfinAPIClient(port: 9999)
        #expect(client.baseURL.absoluteString == "http://localhost:9999")
    }

    @Test("Health check returns false for non-existent server")
    func healthCheckFails() async {
        let client = JellyfinAPIClient(port: 1) // nothing on port 1
        let healthy = await client.isHealthy()
        #expect(healthy == false)
    }
}
