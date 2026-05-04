import Foundation
import HavenFacade
import HavenCore
import os

private let log = Logger(subsystem: "com.haven", category: "FileBrowserFilesFacade")

@MainActor
@Observable
package final class FileBrowserFilesFacade: FilesFacade {
    package let capabilityID: String

    // MARK: - CapabilityFacade

    package private(set) var state: CapabilityState = .idle
    package private(set) var health: CapabilityHealth = .unknown
    package private(set) var advancedURL: URL?

    // MARK: - FilesFacade

    package private(set) var roots: [FilesRoot] = []
    package private(set) var folderState = FilesFolderState(
        root: nil,
        currentPath: nil
    )

    // MARK: - ConnectableFacade

    package let backendName = "File Browser"
    package var setupPhase: SetupPhase?
    package private(set) var connectionState: ConnectionState = .disconnected
    package private(set) var isAutoConnecting = false
    package private(set) var autoConnectExhausted = false
    package var scanErrors: [String] { [] }

    package var setupState: BackendSetupState {
        switch connectionState {
        case .connected:
            .ready
        case .connecting:
            .settingUp
        case .disconnected:
            .needsSetup(message: "Connect to see browser access credentials")
        case .failed(let message):
            .failed(message)
        }
    }

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

    package var deviceAccessInfo: DeviceAccessInfo? {
        guard let port, connectionState == .connected else { return nil }
        let hostname = ProcessInfo.processInfo.hostName
        return DeviceAccessInfo(
            serverAddress: "http://\(hostname):\(port)",
            username: connectedUsername,
            password: connectedPassword
        )
    }

    // MARK: - Internal

    private let lifecycle: FacadeLifecycle
    private weak var serviceManager: ServiceManager?
    private var port: Int?
    private let fileManager: FileManager

    package init(
        capabilityID: String,
        serviceManager: ServiceManager,
        fileManager: FileManager = .default
    ) {
        self.capabilityID = capabilityID
        self.lifecycle = FacadeLifecycle(serviceManager: serviceManager)
        self.serviceManager = serviceManager
        self.fileManager = fileManager
        refresh()
    }

    package var availableActions: [CapabilityAction] {
        switch state {
        case .ready, .degraded:
            var actions: [CapabilityAction] = [.stop, .restart]
            if advancedURL != nil {
                actions.insert(.openInBrowser, at: 0)
            }
            actions.append(.remove)
            return actions
        case .idle, .error:
            return [.start, .remove]
        case .starting:
            return []
        }
    }

    package func perform(_ action: CapabilityAction) async throws {
        let handled = try await lifecycle.perform(action, capabilityID: capabilityID)
        if !handled {
            throw FacadeError.actionNotAvailable(action.id)
        }
    }

    package func refresh() {
        let result = lifecycle.refreshState(for: capabilityID)
        state = result.state
        health = result.health
        advancedURL = result.advancedURL
        port = result.service?.port
        roots = loadRoots()

        if UserDefaults.standard.string(forKey: usernameKey) != nil,
           UserDefaults.standard.string(forKey: passwordKey) != nil {
            connectionState = .connected
            autoConnectExhausted = false
        } else {
            connectionState = .disconnected
        }

        if folderState.root == nil || folderState.currentPath == nil {
            setFolder(root: roots.first, path: roots.first?.path)
        } else {
            reloadCurrentFolder()
        }
    }

    // MARK: - FilesFacade

    package func openRoot(_ root: FilesRoot) async {
        setFolder(root: root, path: root.path)
    }

    package func openFolder(_ item: FilesItem) async {
        guard item.kind == .folder,
              let root = folderState.root,
              isPath(item.path, inside: root.path) else { return }
        setFolder(root: root, path: item.path)
    }

    package func navigateUp() async {
        guard let root = folderState.root,
              let currentPath = folderState.currentPath else { return }
        let rootURL = URL(fileURLWithPath: root.path).standardizedFileURL
        let currentURL = URL(fileURLWithPath: currentPath).standardizedFileURL
        guard currentURL.path != rootURL.path else { return }
        let parent = currentURL.deletingLastPathComponent().standardizedFileURL
        guard isPath(parent.path, inside: rootURL.path) else { return }
        setFolder(root: root, path: parent.path)
    }

    package func refreshItems() async {
        reloadCurrentFolder()
    }

    package func createFolder(named name: String) async throws {
        let safeName = try validatedName(name)
        guard let currentPath = folderState.currentPath else {
            throw FilesFacadeError.noFolderSelected
        }
        let url = URL(fileURLWithPath: currentPath).appendingPathComponent(safeName)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        reloadCurrentFolder()
    }

    package func rename(_ item: FilesItem, to newName: String) async throws {
        let safeName = try validatedName(newName)
        guard let root = folderState.root,
              isPath(item.path, inside: root.path) else {
            throw FilesFacadeError.outsideRoot
        }
        let source = URL(fileURLWithPath: item.path)
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent(safeName)
        guard isPath(destination.path, inside: root.path) else {
            throw FilesFacadeError.outsideRoot
        }
        try fileManager.moveItem(at: source, to: destination)
        reloadCurrentFolder()
    }

    package func moveToTrash(_ item: FilesItem) async throws {
        guard let root = folderState.root,
              isPath(item.path, inside: root.path) else {
            throw FilesFacadeError.outsideRoot
        }
        var trashedURL: NSURL?
        try fileManager.trashItem(
            at: URL(fileURLWithPath: item.path),
            resultingItemURL: &trashedURL
        )
        reloadCurrentFolder()
    }

    // MARK: - Auth

    package func createAccount(username: String, password: String) async throws {
        saveCredentials(username: username, password: password, managed: false)
        connectionState = .connected
    }

    package func connect(username: String, password: String) async throws {
        saveCredentials(username: username, password: password, managed: false)
        connectionState = .connected
    }

    package func disconnect() {
        connectionState = .disconnected
    }

    package func signOut() {
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: passwordKey)
        UserDefaults.standard.removeObject(forKey: managedUserKey)
        UserDefaults.standard.removeObject(forKey: managedPassKey)
        connectionState = .disconnected
    }

    package func switchToManaged() {
        isManagedByHaven = true
        if let username = UserDefaults.standard.string(forKey: managedUserKey),
           let password = UserDefaults.standard.string(forKey: managedPassKey) {
            saveCredentials(username: username, password: password, managed: true)
            connectionState = .connected
        } else {
            connectionState = .disconnected
        }
    }

    package func switchToCustom() {
        isManagedByHaven = false
        disconnect()
    }

    package func autoConnect() async {
        isAutoConnecting = true
        defer { isAutoConnecting = false }

        if UserDefaults.standard.string(forKey: usernameKey) != nil,
           UserDefaults.standard.string(forKey: passwordKey) != nil {
            connectionState = .connected
            autoConnectExhausted = false
        } else {
            connectionState = .failed("No saved File Browser credentials")
            autoConnectExhausted = true
        }
    }

    // MARK: - Folder Loading

    private func loadRoots() -> [FilesRoot] {
        guard let state = serviceManager?.storedState(for: capabilityID) else {
            return []
        }

        let rawPath = state.resolvedSettings["root_path"]
            ?? state.resolvedSettings["content_paths"]?.split(separator: ";").first.map(String.init)
            ?? "~/Documents"
        let path = NSString(string: rawPath).expandingTildeInPath
        let label = URL(fileURLWithPath: path).lastPathComponent
        return [FilesRoot(id: "primary", path: path, label: label.isEmpty ? "Files" : label)]
    }

    private func setFolder(root: FilesRoot?, path: String?) {
        guard let root, let path else {
            folderState = FilesFolderState(root: nil, currentPath: nil)
            return
        }
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        do {
            let items = try loadItems(at: standardizedPath, rootPath: root.path)
            folderState = FilesFolderState(
                root: root,
                currentPath: standardizedPath,
                items: items
            )
        } catch {
            folderState = FilesFolderState(
                root: root,
                currentPath: standardizedPath,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func reloadCurrentFolder() {
        setFolder(root: folderState.root, path: folderState.currentPath)
    }

    private func loadItems(at path: String, rootPath: String) throws -> [FilesItem] {
        guard isPath(path, inside: rootPath) else {
            throw FilesFacadeError.outsideRoot
        }

        let directoryURL = URL(fileURLWithPath: path)
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .isHiddenKey,
            ],
            options: [.skipsHiddenFiles]
        )

        return try urls.map { url in
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ])
            let isDirectory = values.isDirectory == true
            return FilesItem(
                name: url.lastPathComponent,
                path: url.standardizedFileURL.path,
                kind: isDirectory ? .folder : .file,
                byteCount: isDirectory ? nil : Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate
            )
        }
        .sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .folder
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func isPath(_ path: String, inside rootPath: String) -> Bool {
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private func validatedName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FilesFacadeError.invalidName }
        guard !name.contains("/") && name != "." && name != ".." else {
            throw FilesFacadeError.invalidName
        }
        return name
    }

    private func saveCredentials(username: String, password: String, managed: Bool) {
        UserDefaults.standard.set(username, forKey: usernameKey)
        UserDefaults.standard.set(password, forKey: passwordKey)
        UserDefaults.standard.set(!managed, forKey: customAccountKey)
        if managed {
            UserDefaults.standard.set(username, forKey: managedUserKey)
            UserDefaults.standard.set(password, forKey: managedPassKey)
        }
    }

    private var usernameKey: String { "haven.filebrowser.username.\(capabilityID)" }
    private var passwordKey: String { "haven.filebrowser.password.\(capabilityID)" }
    private var managedUserKey: String { "haven.filebrowser.managedUser.\(capabilityID)" }
    private var managedPassKey: String { "haven.filebrowser.managedPass.\(capabilityID)" }
    private var customAccountKey: String { "haven.filebrowser.customAccount.\(capabilityID)" }
}

private enum FilesFacadeError: LocalizedError {
    case noFolderSelected
    case invalidName
    case outsideRoot

    var errorDescription: String? {
        switch self {
        case .noFolderSelected:
            "No folder is selected."
        case .invalidName:
            "Use a name without slashes or reserved path segments."
        case .outsideRoot:
            "That item is outside the selected Files folder."
        }
    }
}
