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
        if setupPhase != nil { return .settingUp }
        switch connectionState {
        case .connected:
            return .ready
        case .connecting:
            return .settingUp
        case .disconnected:
            return .needsSetup(message: "Connect to see browser access credentials")
        case .failed(let message):
            return .failed(message)
        }
    }

    package var isManagedByHaven: Bool {
        get { !UserDefaults.standard.bool(forKey: customAccountKey) }
        set { UserDefaults.standard.set(!newValue, forKey: customAccountKey) }
    }

    package var connectedUsername: String? {
        guard connectionState == .connected else { return nil }
        return credential(.username)
    }

    package var connectedPassword: String? {
        guard connectionState == .connected else { return nil }
        return credential(.password)
    }

    package var deviceAccessInfo: DeviceAccessInfo? {
        guard let port, connectionState == .connected else { return nil }
        let hostname = ProcessInfo.processInfo.hostName
        return DeviceAccessInfo(
            serverAddress: "http://\(hostname):\(port)",
            localAddress: "http://localhost:\(port)",
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
        HavenCredentialStore.shared.migrateLegacyCredentials(
            for: .filebrowser,
            capabilityID: capabilityID
        )
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
        persistRootPathsIfNeeded(roots.map(\.path))
        syncServedRoots()

        if state == .ready && !isSetupComplete && setupPhase == nil {
            setupPhase = .awaitingAccountChoice
        }

        let hasCredentials = credential(.username) != nil
            && credential(.password) != nil
        if hasCredentials && (isSetupComplete || setupPhase == .awaitingLibraryPath) {
            connectionState = .connected
            autoConnectExhausted = false
        } else {
            connectionState = .disconnected
        }

        if let currentRoot = folderState.root,
           let refreshedRoot = roots.first(where: { $0.path == currentRoot.path }),
           let currentPath = folderState.currentPath,
           isPath(currentPath, inside: refreshedRoot.path) {
            setFolder(root: refreshedRoot, path: currentPath)
        } else {
            setFolder(root: roots.first, path: roots.first?.path)
        }
    }

    // MARK: - FilesFacade

    package func openRoot(_ root: FilesRoot) async {
        setFolder(root: root, path: root.path)
    }

    package func addRoot(path: String) async throws {
        let normalizedPath = try normalizedDirectoryPath(path)
        var paths = roots.map(\.path)
        guard !paths.contains(normalizedPath) else {
            throw FilesFacadeError.duplicateRoot
        }
        paths.append(normalizedPath)
        persistRootPaths(paths)
        roots = makeRoots(from: paths)
        syncServedRoots()

        if let root = roots.first(where: { $0.path == normalizedPath }) {
            setFolder(root: root, path: root.path)
        }
    }

    package func removeRoot(_ root: FilesRoot) async throws {
        guard roots.count > 1 else {
            throw FilesFacadeError.lastRoot
        }
        let normalizedPath = URL(fileURLWithPath: root.path).standardizedFileURL.path
        let paths = roots.map(\.path).filter { $0 != normalizedPath }
        guard paths.count != roots.count else { return }

        persistRootPaths(paths)
        roots = makeRoots(from: paths)
        syncServedRoots()

        if folderState.root?.path == normalizedPath {
            setFolder(root: roots.first, path: roots.first?.path)
        } else if let currentRoot = folderState.root,
                  let refreshedRoot = roots.first(where: { $0.path == currentRoot.path }) {
            setFolder(root: refreshedRoot, path: folderState.currentPath)
        }
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
        try await addBackendUser(username: username, password: password)
        saveCredentials(username: username, password: password, managed: false)
        connectionState = .connected
    }

    package func connect(username: String, password: String) async throws {
        saveCredentials(username: username, password: password, managed: false)
        connectionState = .connected
    }

    package func chooseManaged() {
        guard setupPhase == .awaitingAccountChoice else { return }
        isManagedByHaven = true
        setupPhase = .creatingAccount

        let username = credential(.managedUser) ?? "haven"
        let password = credential(.managedPass)
            ?? Self.generatePassword()
        saveCredentials(username: username, password: password, managed: true)
        connectionState = .connected
        setupPhase = .awaitingLibraryPath
    }

    package func chooseCustom() {
        guard setupPhase == .awaitingAccountChoice else { return }
        isManagedByHaven = false
    }

    package func continueSetupAfterLogin() {
        guard connectionState == .connected else { return }
        if setupPhase == .awaitingAccountChoice || setupPhase == nil {
            setupPhase = .awaitingLibraryPath
        }
    }

    package func confirmSetupFolder(_ path: String) async throws {
        guard setupPhase == .awaitingLibraryPath else { return }
        setupPhase = .creatingLibrary
        let normalizedPath = try normalizedDirectoryPath(path)
        persistRootPaths([normalizedPath])
        roots = makeRoots(from: [normalizedPath])
        syncServedRoots()

        if let root = roots.first {
            setFolder(root: root, path: root.path)
        }

        UserDefaults.standard.set(true, forKey: setupCompleteKey)
        setupPhase = nil
        connectionState = .connected
    }

    package func disconnect() {
        connectionState = .disconnected
    }

    package func signOut() {
        HavenCredentialStore.shared.removeAll(for: .filebrowser, capabilityID: capabilityID)
        connectionState = .disconnected
    }

    package func switchToManaged() {
        isManagedByHaven = true
        if let username = credential(.managedUser),
           let password = credential(.managedPass) {
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

        if credential(.username) != nil,
           credential(.password) != nil {
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

        let paths: [String]
        if let unified = state.resolvedSettings["content_paths"], !unified.isEmpty {
            paths = parseRootPaths(unified)
        } else if let rootPath = state.resolvedSettings["root_path"], !rootPath.isEmpty {
            paths = [rootPath]
        } else {
            paths = ["~/Documents"]
        }
        return makeRoots(from: paths)
    }

    private func parseRootPaths(_ rawValue: String) -> [String] {
        rawValue.split(separator: ";")
            .map(String.init)
            .map(expandAndStandardize)
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { paths, path in
                if !paths.contains(path) {
                    paths.append(path)
                }
            }
    }

    private func makeRoots(from paths: [String]) -> [FilesRoot] {
        var usedLabels: [String: Int] = [:]
        return paths
            .map(expandAndStandardize)
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { uniquePaths, path in
                if !uniquePaths.contains(path) {
                    uniquePaths.append(path)
                }
            }
            .map { path in
                let label = uniqueLabel(for: path, usedLabels: &usedLabels)
                return FilesRoot(id: path, path: path, label: label)
            }
    }

    private func uniqueLabel(
        for path: String,
        usedLabels: inout [String: Int]
    ) -> String {
        let base = URL(fileURLWithPath: path).lastPathComponent
        let fallback = path == "/" ? "Macintosh HD" : "Files"
        let label = base.isEmpty ? fallback : base
        let count = usedLabels[label, default: 0] + 1
        usedLabels[label] = count
        return count == 1 ? label : "\(label) \(count)"
    }

    private func expandAndStandardize(_ path: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private func normalizedDirectoryPath(_ path: String) throws -> String {
        guard !path.contains(";") else {
            throw FilesFacadeError.invalidRoot
        }
        let normalizedPath = expandAndStandardize(path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: normalizedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FilesFacadeError.rootNotFound
        }
        return normalizedPath
    }

    private func persistRootPathsIfNeeded(_ paths: [String]) {
        guard let state = serviceManager?.storedState(for: capabilityID) else { return }
        let joined = paths.joined(separator: ";")
        if state.resolvedSettings["content_paths"] != joined {
            persistRootPaths(paths)
        }
    }

    private func persistRootPaths(_ paths: [String]) {
        let normalizedPaths = paths
            .map(expandAndStandardize)
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, path in
                if !result.contains(path) {
                    result.append(path)
                }
            }
        guard !normalizedPaths.isEmpty else { return }

        serviceManager?.updateResolvedSetting(
            for: capabilityID,
            key: "root_path",
            value: normalizedPaths[0]
        )
        serviceManager?.updateResolvedSetting(
            for: capabilityID,
            key: "content_paths",
            value: normalizedPaths.joined(separator: ";")
        )
    }

    private func syncServedRoots() {
        guard let servedDirectory = servedRootsDirectory else { return }

        do {
            try fileManager.createDirectory(
                at: servedDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            log.warning("Failed to create served roots directory: \(error.localizedDescription)")
            return
        }

        let desiredLabels = Set(roots.map(\.label))
        if let existing = try? fileManager.contentsOfDirectory(
            at: servedDirectory,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in existing where !desiredLabels.contains(url.lastPathComponent) {
                if isSymbolicLink(url) {
                    do {
                        try fileManager.removeItem(at: url)
                    } catch {
                        log.warning("Failed to remove stale served root \(url.path): \(error.localizedDescription)")
                    }
                }
            }
        }

        for root in roots {
            let link = servedDirectory.appendingPathComponent(root.label)
            if isSymbolicLink(link),
               (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) == root.path {
                continue
            }
            if fileManager.fileExists(atPath: link.path) {
                if isSymbolicLink(link) {
                    try? fileManager.removeItem(at: link)
                } else {
                    log.warning("Cannot expose root \(root.path); served label already exists: \(link.path)")
                    continue
                }
            }
            do {
                try fileManager.createSymbolicLink(
                    atPath: link.path,
                    withDestinationPath: root.path
                )
            } catch {
                log.warning("Failed to expose root \(root.path): \(error.localizedDescription)")
            }
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private var servedRootsDirectory: URL? {
        serviceManager?.storedState(for: capabilityID)?
            .directoryLayout
            .data
            .appendingPathComponent("served-roots")
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
        setCredential(username, .username)
        setCredential(password, .password)
        UserDefaults.standard.set(!managed, forKey: customAccountKey)
        if managed {
            setCredential(username, .managedUser)
            setCredential(password, .managedPass)
        }
    }

    private func credential(_ purpose: HavenCredentialPurpose) -> String? {
        HavenCredentialStore.shared.string(
            for: .filebrowser,
            purpose,
            capabilityID: capabilityID
        )
    }

    private func setCredential(_ value: String, _ purpose: HavenCredentialPurpose) {
        HavenCredentialStore.shared.set(
            value,
            for: .filebrowser,
            purpose,
            capabilityID: capabilityID
        )
    }

    private func addBackendUser(username: String, password: String) async throws {
        guard let executableURL = fileBrowserExecutableURL,
              let databaseURL = databaseURL else {
            return
        }

        try await Task.detached {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = [
                "users", "add",
                username, password,
                "--database", databaseURL.path,
                "--scope", ".",
                "--perm.admin",
            ]

            let pipe = Pipe()
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw FilesFacadeError.accountCreationFailed(
                    message?.isEmpty == false ? message! : "Could not create File Browser account."
                )
            }
        }.value
    }

    private var fileBrowserExecutableURL: URL? {
        guard let artifact = serviceManager?.storedState(for: capabilityID)?
            .artifactInfo
            .first(where: { $0.unitID == "haven.unit.filebrowser" }) else {
            return nil
        }

        let entrypoint = artifact.entrypoint ?? "filebrowser"
        if entrypoint.hasPrefix("/") {
            return URL(fileURLWithPath: entrypoint)
        }

        let relative = entrypoint.hasPrefix("./")
            ? String(entrypoint.dropFirst(2))
            : entrypoint
        return URL(fileURLWithPath: artifact.installDirectory)
            .appendingPathComponent(relative)
    }

    private var databaseURL: URL? {
        serviceManager?.storedState(for: capabilityID)?
            .directoryLayout
            .data
            .appendingPathComponent("filebrowser.db")
    }

    private var isSetupComplete: Bool {
        UserDefaults.standard.bool(forKey: setupCompleteKey)
    }

    private var customAccountKey: String { "haven.filebrowser.customAccount.\(capabilityID)" }
    private var setupCompleteKey: String { "haven.filebrowser.setupComplete.\(capabilityID)" }

    private static func generatePassword() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz"
        let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let digits = "0123456789"
        let special = "!@#$%^&*"
        var chars: [Character] = [
            letters.randomElement()!,
            upper.randomElement()!,
            digits.randomElement()!,
            special.randomElement()!,
        ]
        let all = letters + upper + digits + special
        for _ in 0..<12 {
            chars.append(all.randomElement()!)
        }
        chars.shuffle()
        return String(chars)
    }
}

private enum FilesFacadeError: LocalizedError {
    case noFolderSelected
    case invalidName
    case invalidRoot
    case rootNotFound
    case duplicateRoot
    case lastRoot
    case outsideRoot
    case accountCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFolderSelected:
            "No folder is selected."
        case .invalidName:
            "Use a name without slashes or reserved path segments."
        case .invalidRoot:
            "Choose a folder path that does not contain reserved separators."
        case .rootNotFound:
            "That folder does not exist."
        case .duplicateRoot:
            "That folder is already in Files."
        case .lastRoot:
            "Files needs at least one folder."
        case .outsideRoot:
            "That item is outside the selected Files folder."
        case .accountCreationFailed(let message):
            message
        }
    }
}
