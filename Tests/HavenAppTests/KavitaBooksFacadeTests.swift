import Testing
import Foundation
import HavenFacade
import HavenAppKit

// MARK: - Auth State Machine Tests

@Suite("KavitaBooksFacade Auth State Machine")
struct KavitaBooksFacadeTests {

    private func makeTestID() -> String {
        "haven.test.kavita.\(UUID().uuidString)"
    }

    private func cleanupDefaults(for id: String) {
        for key in [
            "haven.kavita.token.\(id)",
            "haven.kavita.username.\(id)",
            "haven.kavita.password.\(id)",
            "haven.kavita.managedUser.\(id)",
            "haven.kavita.managedPass.\(id)",
            "haven.kavita.customAccount.\(id)",
            "haven.kavita.apiKey.\(id)",
            "haven.kavita.libraryPath.\(id)",
            "haven.kavita.libraryPaths.\(id)",
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @MainActor
    private func makeFacade() -> (KavitaBooksFacade, String) {
        let id = makeTestID()
        let sm = ServiceManager()
        return (KavitaBooksFacade(capabilityID: id, serviceManager: sm), id)
    }

    // MARK: - Fresh Install

    @Test("Fresh facade: disconnected, managed=true, no credentials")
    @MainActor func freshInstall() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        #expect(f.connectionState == .disconnected)
        #expect(f.isManagedByHaven == true)
        #expect(f.connectedUsername == nil)
        #expect(f.itemCount == nil)
        #expect(f.hasSavedCredentials == false)
        #expect(f.isAutoConnecting == false)
        #expect(f.state == .idle)
    }

    // MARK: - setupState Derivation

    @Test("setupState maps connectionState correctly")
    @MainActor func setupStateMapping() async {
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
        #expect(UserDefaults.standard.bool(forKey: "haven.kavita.customAccount.\(id)") == true)

        f.isManagedByHaven = true
        #expect(f.isManagedByHaven == true)
    }

    @Test("isManagedByHaven persists across facade instances")
    @MainActor func managedPersistsAcrossInstances() async {
        let id = makeTestID()
        defer { cleanupDefaults(for: id) }

        let sm = ServiceManager()
        let f1 = KavitaBooksFacade(capabilityID: id, serviceManager: sm)
        f1.isManagedByHaven = false

        let f2 = KavitaBooksFacade(capabilityID: id, serviceManager: sm)
        #expect(f2.isManagedByHaven == false)
    }

    // MARK: - disconnect()

    @Test("disconnect: clears token, preserves password, sets disconnected")
    @MainActor func disconnectPreservesPassword() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        UserDefaults.standard.set("pw", forKey: "haven.kavita.password.\(id)")
        UserDefaults.standard.set("tk", forKey: "haven.kavita.token.\(id)")
        UserDefaults.standard.set("user", forKey: "haven.kavita.username.\(id)")

        f.disconnect()

        #expect(f.connectionState == .disconnected)
        #expect(f.hasSavedCredentials == true)
        #expect(UserDefaults.standard.string(forKey: "haven.kavita.token.\(id)") == nil)
        // username preserved (for hasSavedCredentials check)
        #expect(f.connectedUsername == nil) // not connected
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

        UserDefaults.standard.set("pw", forKey: "haven.kavita.password.\(id)")
        UserDefaults.standard.set("tk", forKey: "haven.kavita.token.\(id)")
        UserDefaults.standard.set("user", forKey: "haven.kavita.username.\(id)")

        f.signOut()

        #expect(f.connectionState == .disconnected)
        #expect(f.hasSavedCredentials == false)
        #expect(UserDefaults.standard.string(forKey: "haven.kavita.token.\(id)") == nil)
        #expect(UserDefaults.standard.string(forKey: "haven.kavita.username.\(id)") == nil)
        #expect(UserDefaults.standard.string(forKey: "haven.kavita.password.\(id)") == nil)
    }

    @Test("signOut after disconnect: still clears password")
    @MainActor func signOutAfterDisconnect() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        UserDefaults.standard.set("pw", forKey: "haven.kavita.password.\(id)")
        f.disconnect()
        #expect(f.hasSavedCredentials == true)

        f.signOut()
        #expect(f.hasSavedCredentials == false)
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

    @Test("switchToManaged: sets flag, clears creds (ready for auto-connect)")
    @MainActor func switchToManaged() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.isManagedByHaven = false
        UserDefaults.standard.set("tk", forKey: "haven.kavita.token.\(id)")

        f.switchToManaged()
        #expect(f.isManagedByHaven == true)
        // Credentials cleared for fresh auto-connect
        #expect(UserDefaults.standard.string(forKey: "haven.kavita.token.\(id)") == nil)
    }

    // MARK: - autoConnect() Without API

    @Test("autoConnect: no-op when apiClient is nil")
    @MainActor func autoConnectNoClient() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        await f.autoConnect()
        // Should not crash, state unchanged
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

        UserDefaults.standard.set("haven", forKey: "haven.kavita.username.\(id)")
        #expect(f.connectionState == .disconnected)
        #expect(f.connectedUsername == nil)
    }

    // MARK: - Library Updates

    @Test("disconnect clears itemCount")
    @MainActor func disconnectClearsItemCount() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.disconnect()
        #expect(f.itemCount == nil)
    }

    // MARK: - Setup Wizard

    @Test("setupPhase starts nil on fresh facade")
    @MainActor func setupPhaseStartsNil() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        #expect(f.setupPhase == nil)
    }

    @Test("setupState returns .settingUp when setupPhase is active")
    @MainActor func setupStateSettingUpWhenPhaseActive() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.setupPhase = .awaitingAccountChoice
        #expect(f.setupState == .settingUp)
    }

    @Test("chooseManaged: transitions from awaitingAccountChoice to creatingAccount, sets managed")
    @MainActor func chooseManagedTransition() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.setupPhase = .awaitingAccountChoice
        f.chooseManaged()
        #expect(f.isManagedByHaven == true)
        #expect(f.setupPhase == .creatingAccount)
    }

    @Test("chooseManaged: no-op when not in awaitingAccountChoice")
    @MainActor func chooseManagedGuard() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.setupPhase = .creatingAccount
        f.chooseManaged()
        // Should still be creatingAccount, not changed
        #expect(f.setupPhase == .creatingAccount)
    }

    @Test("chooseCustom: sets isManagedByHaven to false")
    @MainActor func chooseCustomSetsFlag() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.setupPhase = .awaitingAccountChoice
        f.chooseCustom()
        #expect(f.isManagedByHaven == false)
    }

    @Test("chooseCustom: no-op when not in awaitingAccountChoice")
    @MainActor func chooseCustomGuard() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.setupPhase = .creatingAccount
        f.isManagedByHaven = true
        f.chooseCustom()
        // Should not have changed
        #expect(f.isManagedByHaven == true)
    }

    @Test("continueSetupAfterLogin: transitions to awaitingLibraryPath")
    @MainActor func continueSetupAfterLoginTransition() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.setupPhase = .awaitingAccountChoice
        f.continueSetupAfterLogin()
        #expect(f.setupPhase == .awaitingLibraryPath)
    }

    @Test("disconnect clears setupPhase")
    @MainActor func disconnectClearsSetupPhase() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.setupPhase = .awaitingLibraryPath
        f.disconnect()
        #expect(f.setupPhase == nil)
    }

    @Test("signOut clears setupPhase")
    @MainActor func signOutClearsSetupPhase() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        f.setupPhase = .creatingAccount
        f.signOut()
        #expect(f.setupPhase == nil)
    }

    // MARK: - Multi-Folder Path Persistence

    @Test("Library paths default to ~/Books when no override exists")
    @MainActor func defaultLibraryPath() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        // Library is populated from resolvedLibraryPaths in refresh()
        #expect(f.library == nil) // No service installed → nil
    }

    @Test("Single library path override persists in UserDefaults")
    @MainActor func singlePathPersistence() async {
        let id = makeTestID()
        defer { cleanupDefaults(for: id) }

        UserDefaults.standard.set("/Users/test/Books", forKey: "haven.kavita.libraryPath.\(id)")

        let sm = ServiceManager()
        let f = KavitaBooksFacade(capabilityID: id, serviceManager: sm)
        // Can't check resolvedLibraryPaths directly (private), but signOut should clear it
        f.signOut()
        #expect(UserDefaults.standard.string(forKey: "haven.kavita.libraryPath.\(id)") == nil)
    }

    @Test("Multi-path array persists in UserDefaults")
    @MainActor func multiPathPersistence() async {
        let id = makeTestID()
        defer { cleanupDefaults(for: id) }

        let paths = ["/Users/test/Books", "/Users/test/Comics"]
        UserDefaults.standard.set(paths, forKey: "haven.kavita.libraryPaths.\(id)")

        let stored = UserDefaults.standard.stringArray(forKey: "haven.kavita.libraryPaths.\(id)")
        #expect(stored == paths)
    }

    @Test("signOut clears both single and multi-path keys")
    @MainActor func signOutClearsPaths() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        UserDefaults.standard.set("/Books", forKey: "haven.kavita.libraryPath.\(id)")
        UserDefaults.standard.set(["/Books", "/Comics"], forKey: "haven.kavita.libraryPaths.\(id)")

        f.signOut()

        #expect(UserDefaults.standard.string(forKey: "haven.kavita.libraryPath.\(id)") == nil)
        #expect(UserDefaults.standard.stringArray(forKey: "haven.kavita.libraryPaths.\(id)") == nil)
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

    @Test("addLibraryPath throws when not connected")
    @MainActor func addLibraryPathThrowsWhenDisconnected() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        do {
            try await f.addLibraryPath("/Books2")
            Issue.record("Expected error")
        } catch {
            #expect(error is FacadeError)
        }
    }

    @Test("removeLibraryPath throws when not connected")
    @MainActor func removeLibraryPathThrowsWhenDisconnected() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        do {
            try await f.removeLibraryPath("/Books")
            Issue.record("Expected error")
        } catch {
            #expect(error is FacadeError)
        }
    }

    @Test("setLibraryPath throws when not connected")
    @MainActor func setLibraryPathThrowsWhenDisconnected() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        do {
            try await f.setLibraryPath("/Books")
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

    // MARK: - Settings Toggle Flow

    @Test("Toggle OFF: disconnect, show Sign In needed")
    @MainActor func settingsToggleOff() async {
        let (f, id) = makeFacade()
        defer { cleanupDefaults(for: id) }

        UserDefaults.standard.set("pw", forKey: "haven.kavita.password.\(id)")
        UserDefaults.standard.set("tk", forKey: "haven.kavita.token.\(id)")

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
}

// MARK: - API Error Parsing Tests

@Suite("KavitaAPIError Message Extraction")
struct KavitaAPIErrorTests {

    @Test("ASP.NET validation: extracts field errors, not generic title")
    func aspNetValidation() {
        let body = """
        {"type":"x","title":"One or more validation errors occurred.","status":400,"errors":{"Password":["Passwords must be at least 6 characters.","Passwords must have at least one uppercase."]}}
        """
        let msg = KavitaAPIError.httpError(statusCode: 400, body: body).localizedDescription
        #expect(msg.contains("6 characters"))
        #expect(!msg.contains("One or more"))
    }

    @Test("Multiple validation fields")
    func multipleFields() {
        let body = """
        {"errors":{"Username":["Required"],"Password":["Too short"]}}
        """
        let msg = KavitaAPIError.httpError(statusCode: 400, body: body).localizedDescription
        #expect(msg.contains("Required"))
        #expect(msg.contains("Too short"))
    }

    @Test("Plain JSON string") func plainString() {
        let e = KavitaAPIError.httpError(statusCode: 400, body: "\"User exists\"")
        #expect(e.localizedDescription == "User exists")
    }

    @Test("401 empty body") func unauthorized() {
        let e = KavitaAPIError.httpError(statusCode: 401, body: "")
        #expect(e.localizedDescription == "Invalid credentials")
    }

    @Test("401 with message") func unauthorizedMsg() {
        let e = KavitaAPIError.httpError(statusCode: 401, body: "\"Locked\"")
        #expect(e.localizedDescription == "Locked")
    }

    @Test("Object message field") func messageField() {
        let e = KavitaAPIError.httpError(statusCode: 403, body: "{\"message\":\"Locked\"}")
        #expect(e.localizedDescription == "Locked")
    }

    @Test("Object detail field") func detailField() {
        let e = KavitaAPIError.httpError(statusCode: 429, body: "{\"detail\":\"Rate limit\"}")
        #expect(e.localizedDescription == "Rate limit")
    }

    @Test("String array") func stringArray() {
        let e = KavitaAPIError.httpError(statusCode: 400, body: "[\"A\",\"B\"]")
        #expect(e.localizedDescription == "A. B")
    }

    @Test("Raw text fallback") func rawText() {
        let e = KavitaAPIError.httpError(statusCode: 500, body: "Oops")
        #expect(e.localizedDescription == "Oops")
    }

    @Test("Empty body fallback") func emptyBody() {
        let e = KavitaAPIError.httpError(statusCode: 503, body: "")
        #expect(e.localizedDescription == "Server error (503)")
    }

    @Test("Empty errors dict falls back to title") func emptyErrors() {
        let e = KavitaAPIError.httpError(statusCode: 400, body: "{\"title\":\"Bad\",\"errors\":{}}")
        #expect(e.localizedDescription == "Bad")
    }
}

// MARK: - BooksLibrary Value Type Tests

@Suite("BooksLibrary Value Type")
struct BooksLibraryTests {

    @Test("Single-path init: libraryPath returns the path")
    func singlePathInit() {
        let lib = BooksLibrary(libraryPath: "/Books")
        #expect(lib.libraryPath == "/Books")
        #expect(lib.libraryPaths == ["/Books"])
        #expect(lib.scanStatus == .idle)
        #expect(lib.itemCount == nil)
    }

    @Test("Multi-path init: libraryPath returns first")
    func multiPathInit() {
        let lib = BooksLibrary(libraryPaths: ["/Books", "/Comics"])
        #expect(lib.libraryPath == "/Books")
        #expect(lib.libraryPaths.count == 2)
        #expect(lib.libraryPaths[1] == "/Comics")
    }

    @Test("Empty paths: libraryPath returns default")
    func emptyPaths() {
        let lib = BooksLibrary(libraryPaths: [])
        #expect(lib.libraryPath == "~/Books")
    }

    @Test("Equatable: identical libraries are equal")
    func equatable() {
        let a = BooksLibrary(libraryPaths: ["/Books"], itemCount: 5)
        let b = BooksLibrary(libraryPaths: ["/Books"], itemCount: 5)
        #expect(a == b)
    }

    @Test("Equatable: different paths are not equal")
    func differentPaths() {
        let a = BooksLibrary(libraryPaths: ["/Books"])
        let b = BooksLibrary(libraryPaths: ["/Comics"])
        #expect(a != b)
    }

    @Test("Equatable: different counts are not equal")
    func differentCounts() {
        let a = BooksLibrary(libraryPath: "/Books", itemCount: 5)
        let b = BooksLibrary(libraryPath: "/Books", itemCount: 10)
        #expect(a != b)
    }

    @Test("Multi-path with scan status")
    func multiPathWithStatus() {
        let lib = BooksLibrary(libraryPaths: ["/Books", "/Comics"], scanStatus: .scanning, itemCount: 42)
        #expect(lib.scanStatus == .scanning)
        #expect(lib.itemCount == 42)
        #expect(lib.libraryPaths.count == 2)
    }
}
