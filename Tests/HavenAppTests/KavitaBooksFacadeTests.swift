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
