import Foundation
import HavenFacade

/// Mock Books facade for backend replaceability validation.
///
/// Simulates a books backend that uses API key auth instead of
/// username/password. Proves the BooksFacade protocol handles
/// different auth mechanisms through BackendSetupState.
@MainActor
@Observable
final class MockBooksFacade: BooksFacade {
    let capabilityID: String

    // MARK: - CapabilityFacade

    private(set) var state: CapabilityState = .idle
    private(set) var health: CapabilityHealth = .unknown
    private(set) var advancedURL: URL?

    // MARK: - BooksFacade

    private(set) var library: BooksLibrary?

    var setupState: BackendSetupState {
        if apiKey != nil {
            return .ready
        }
        return .needsSetup(message: "Enter your API key to connect")
    }

    // MARK: - Mock-Specific (API Key Auth)

    private(set) var apiKey: String?

    var isConnected: Bool { apiKey != nil }

    // MARK: - Internal

    private let lifecycle: FacadeLifecycle
    private weak var serviceManager: ServiceManager?

    // MARK: - Init

    init(capabilityID: String, serviceManager: ServiceManager) {
        self.capabilityID = capabilityID
        self.serviceManager = serviceManager
        self.lifecycle = FacadeLifecycle(serviceManager: serviceManager)
        refresh()
        loadSavedKey()
    }

    // MARK: - Available Actions

    var availableActions: [CapabilityAction] {
        switch state {
        case .ready:
            var actions: [CapabilityAction] = []
            if apiKey != nil { actions.append(.rescan) }
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
        guard apiKey != nil else {
            throw FacadeError.adapterError("Not connected")
        }
        // Mock: simulate a brief scan
        library = library.map {
            BooksLibrary(libraryPath: $0.libraryPath, scanStatus: .scanning, itemCount: $0.itemCount)
        }
        try await Task.sleep(for: .milliseconds(500))
        library = library.map {
            BooksLibrary(libraryPath: $0.libraryPath, scanStatus: .complete, itemCount: ($0.itemCount ?? 0) + Int.random(in: 0...3))
        }
    }

    // MARK: - API Key Auth

    func connect(apiKey: String) throws {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FacadeError.adapterError("API key cannot be empty")
        }
        self.apiKey = apiKey
        saveKey(apiKey)
        updateLibrary()
    }

    func disconnect() {
        apiKey = nil
        clearSavedKey()
        updateLibrary()
    }

    // MARK: - Refresh

    func refresh() {
        let result = lifecycle.refreshState(for: capabilityID)
        state = result.state
        health = result.health
        advancedURL = result.advancedURL

        guard result.service != nil else {
            library = nil
            return
        }

        // Reset auth on stop/fail
        if state != .ready && state != .starting {
            apiKey = nil
        }

        updateLibrary()

        // Auto-reconnect
        if state == .ready && apiKey == nil {
            loadSavedKey()
        }
    }

    // MARK: - Library

    private func updateLibrary() {
        let stored = serviceManager?.storedState(for: capabilityID)
        let libraryPath = stored?.resolvedSettings["library_path"] ?? "~/Books"

        if apiKey != nil {
            library = BooksLibrary(
                libraryPath: libraryPath,
                scanStatus: .idle,
                itemCount: 42 // Mock data
            )
        } else {
            library = BooksLibrary(
                libraryPath: libraryPath,
                scanStatus: .idle,
                itemCount: nil
            )
        }
    }

    // MARK: - Key Persistence

    private var keyStorageKey: String { "haven.mockbooks.apikey.\(capabilityID)" }

    private func saveKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: keyStorageKey)
    }

    private func loadSavedKey() {
        apiKey = UserDefaults.standard.string(forKey: keyStorageKey)
    }

    private func clearSavedKey() {
        UserDefaults.standard.removeObject(forKey: keyStorageKey)
    }
}
