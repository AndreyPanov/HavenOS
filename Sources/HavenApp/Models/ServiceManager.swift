import Foundation
import HavenCore
import HavenFacade
import HavenExecutor
import HavenRuntimes
import HavenLaunchd
import HavenInstaller
import SwiftUI
import Synchronization
import os

private let log = Logger(subsystem: "com.haven", category: "ServiceManager")

/// Summary counts from a successful catalog load.
struct CatalogCounts: Equatable {
    let capabilities: Int
    let bundles: Int
    let runtimeUnits: Int
}

/// Represents the catalog loading state for the UI.
enum CatalogState: Equatable {
    /// Catalog has not been loaded yet.
    case notLoaded
    /// Catalog loaded successfully with no issues.
    case loaded(counts: CatalogCounts)
    /// Catalog loaded successfully but with non-fatal warnings.
    case loadedWithWarnings(counts: CatalogCounts, warnings: [SpecLoadIssue])
    /// Catalog folder does not exist at the configured path.
    case folderNotFound(path: String)
    /// Catalog failed to load due to errors.
    case issues([SpecLoadIssue])
}

/// Central data layer that bridges HavenCore specs and state to the UI.
///
/// - Discovery: Loads specs from a local folder via `SpecLoader`
/// - Installed: Reads `HavenState` from `FileStateStore` at `~/.haven/`
/// - Lifecycle: Delegates install/uninstall/start/stop to `HavenExecutor`
@MainActor
@Observable
package final class ServiceManager {

    // MARK: - Published Data

    /// Services currently installed (from ~/.haven/State/services.json).
    private(set) var installedServices: [InstalledService] = []

    /// All discoverable plugins (from local catalog specs).
    private(set) var discoverablePlugins: [DiscoverablePlugin] = []

    // MARK: - UI State

    /// True while an install/uninstall/start/stop operation is in progress.
    private(set) var isPerformingAction = false

    /// The capability ID of the service currently being acted on, or nil.
    private(set) var activeCapabilityID: String?

    /// Human-readable status of the current action (e.g. "Setting up Python environment…").
    private(set) var actionStatus: String?

    /// Description of the last error, cleared on next action.
    var lastError: String?

    /// Current catalog loading state for the UI.
    private(set) var catalogState: CatalogState = .notLoaded

    // MARK: - Internal State

    private var catalog: [CatalogEntry] = []
    private var registry: SpecRegistry?
    private var havenState: HavenState = HavenState()
    private let paths: HavenPaths
    private let stateStore: FileStateStore
    private let executor: HavenExecutor

    // MARK: - Facade Layer

    private let adapterRegistry = AdapterRegistry()
    private var facades: [String: any CapabilityFacade] = [:]

    /// Get the facade for an installed capability, creating it on demand.
    func facade(for capabilityID: String) -> (any CapabilityFacade)? {
        guard installedServices.contains(where: { $0.id == capabilityID }) else {
            facades.removeValue(forKey: capabilityID)
            return nil
        }
        if let existing = facades[capabilityID] {
            return existing
        }
        let newFacade = adapterRegistry.createFacade(
            capabilityID: capabilityID,
            serviceManager: self
        )
        facades[capabilityID] = newFacade
        return newFacade
    }

    /// Whether a custom (non-generic) adapter is registered for this capability.
    func hasNativeUI(for capabilityID: String) -> Bool {
        adapterRegistry.hasCustomAdapter(for: capabilityID)
    }

    /// Access persisted service state (settings, ports, layout) for facades.
    func storedState(for capabilityID: String) -> StoredServiceState? {
        havenState.services[capabilityID]
    }

    // MARK: - Init

    package init(basePath: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".haven")) {
        self.paths = HavenPaths(base: basePath)
        self.stateStore = FileStateStore(paths: paths)
        self.executor = HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: LaunchdController(),
            artifactInstaller: ArtifactInstaller(paths: paths),
            pythonPreparer: PythonEnvironmentPreparer(),
            provisionDownloader: ProvisionDownloader(),
            installStepExecutor: InstallStepExecutor(),
            dependencyValidator: DependencyValidator(),
            readinessChecker: ReadinessChecker()
        )

        // Register capability-specific adapters
        adapterRegistry.register(capabilityID: "haven.capability.kavita") { capID, sm in
            KavitaBooksFacade(capabilityID: capID, serviceManager: sm)
        }
        adapterRegistry.register(capabilityID: "haven.capability.navidrome") { capID, sm in
            NavidromeMusicFacade(capabilityID: capID, serviceManager: sm)
        }
        adapterRegistry.register(capabilityID: "haven.capability.jellyfin") { capID, sm in
            JellyfinMoviesFacade(capabilityID: capID, serviceManager: sm)
        }

        log.info("Initialized with base path: \(basePath.path)")
    }

    // MARK: - Loading

    /// Load catalog from the given URL and installed state. Call once on app launch.
    package func load(catalogURL: URL) {
        ensureCatalogFolderExists(at: catalogURL)
        loadCatalog(from: catalogURL)
        loadInstalledState()
        rebuildViewModels()
    }

    /// Reload just the catalog from a (possibly changed) folder URL.
    func reloadCatalog(from catalogURL: URL) {
        log.info("Reloading catalog from: \(catalogURL.path)")
        loadCatalog(from: catalogURL)
        rebuildViewModels()
    }

    /// Reload just the installed state (e.g. after an action).
    func refresh() {
        loadInstalledState()
        rebuildViewModels()
    }

    // MARK: - Lifecycle Actions

    /// Install a service by capability ID. Runs the executor on a background thread.
    func installService(capabilityID: String) async {
        guard let registry = self.registry else {
            lastError = "No catalog loaded. Configure your catalog folder in Settings."
            return
        }

        log.info("Install service: \(capabilityID)")
        isPerformingAction = true
        activeCapabilityID = capabilityID
        actionStatus = "Installing…"
        lastError = nil

        defer {
            isPerformingAction = false
            activeCapabilityID = nil
            actionStatus = nil
        }

        let executor = self.executor
        let progressBox = Mutex<String?>(nil)
        let resultBox = Mutex<Result<StoredServiceState, Error>?>(nil)

        Task.detached {
            do {
                let state = try executor.install(
                    capabilityID: capabilityID,
                    registry: registry,
                    progress: { message in
                        progressBox.withLock { $0 = message }
                    }
                )
                resultBox.withLock { $0 = .success(state) }
            } catch {
                resultBox.withLock { $0 = .failure(error) }
            }
        }

        // Poll for progress updates on MainActor
        while resultBox.withLock({ $0 }) == nil {
            if let message = progressBox.withLock({ $0 }) {
                actionStatus = message
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Handle result
        switch resultBox.withLock({ $0 })! {
        case .success:
            log.info("Install succeeded: \(capabilityID)")
            refresh()

            // Auto-start the service after install
            actionStatus = "Starting…"
            await startService(capabilityID: capabilityID)

        case .failure(let error):
            log.error("Install failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Uninstall a service by capability ID.
    func uninstallService(capabilityID: String) async {
        // Clear facade credentials before uninstall
        clearFacadeCredentials(for: capabilityID)
        facades.removeValue(forKey: capabilityID)

        await performAction("Uninstall", capabilityID: capabilityID) { executor in
            try executor.uninstall(capabilityID: capabilityID)
        }
    }

    /// Remove all UserDefaults keys associated with a facade's credentials.
    private func clearFacadeCredentials(for capabilityID: String) {
        let prefixes = [
            "haven.kavita.", "haven.navidrome.", "haven.jellyfin."
        ]
        let defaults = UserDefaults.standard
        for prefix in prefixes {
            let keys = [
                "\(prefix)token.\(capabilityID)",
                "\(prefix)username.\(capabilityID)",
                "\(prefix)password.\(capabilityID)",
                "\(prefix)managedUser.\(capabilityID)",
                "\(prefix)managedPass.\(capabilityID)",
                "\(prefix)apiKey.\(capabilityID)",
                "\(prefix)customAccount.\(capabilityID)",
                "\(prefix)libraryPath.\(capabilityID)",
                "\(prefix)setupComplete.\(capabilityID)",
            ]
            for key in keys {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Start an installed service. No-op if already running.
    func startService(capabilityID: String) async {
        if let service = installedServices.first(where: { $0.id == capabilityID }),
           service.status == .running {
            return
        }
        await performAsyncAction("Start", capabilityID: capabilityID) { executor in
            try await executor.start(capabilityID: capabilityID)
        }
    }

    /// Stop a running service.
    func stopService(capabilityID: String) async {
        await performAction("Stop", capabilityID: capabilityID) { executor in
            try executor.stop(capabilityID: capabilityID)
        }
    }

    /// Run a lifecycle action on a background thread with standard error handling.
    private func performAction(
        _ label: String,
        capabilityID: String,
        action: @Sendable @escaping (HavenExecutor) throws -> Void
    ) async {
        log.info("\(label) service: \(capabilityID)")
        isPerformingAction = true
        activeCapabilityID = capabilityID
        actionStatus = "\(label)ing…"
        lastError = nil

        let executor = self.executor

        do {
            try await Task.detached {
                try action(executor)
            }.value
            log.info("\(label) succeeded: \(capabilityID)")
            refresh()
        } catch {
            log.error("\(label) failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        isPerformingAction = false
        activeCapabilityID = nil
        actionStatus = nil
    }

    /// Run an async lifecycle action with standard error handling.
    private func performAsyncAction(
        _ label: String,
        capabilityID: String,
        action: @Sendable @escaping (HavenExecutor) async throws -> Void
    ) async {
        log.info("\(label) service: \(capabilityID)")
        isPerformingAction = true
        activeCapabilityID = capabilityID
        actionStatus = "\(label)ing…"
        lastError = nil

        let executor = self.executor

        do {
            try await Task.detached {
                try await action(executor)
            }.value
            log.info("\(label) succeeded: \(capabilityID)")
            refresh()
        } catch {
            log.error("\(label) failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        isPerformingAction = false
        activeCapabilityID = nil
        actionStatus = nil
    }

    // MARK: - Catalog Folder Setup

    /// Ensure the catalog folder exists.
    private func ensureCatalogFolderExists(at url: URL) {
        let fm = FileManager.default

        if !fm.fileExists(atPath: url.path) {
            log.info("Creating default catalog folder at: \(url.path)")
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                log.info("Created catalog folder")
            } catch {
                log.error("Failed to create catalog folder: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Catalog Loading

    private func loadCatalog(from catalogURL: URL) {
        let fm = FileManager.default
        let path = catalogURL.path

        // Start with built-in specs (always available)
        let builtIn = BuiltInCatalog.makeRegistry()
        var caps = builtIn.capabilitiesByID
        var bundles = builtIn.bundlesByID
        var units = builtIn.runtimeUnitsByID
        var diskWarnings: [SpecLoadIssue] = []

        // Merge disk-loaded specs on top (disk specs can add more services)
        if fm.fileExists(atPath: path) {
            log.info("Loading catalog via SpecLoader from: \(path)")
            let result = SpecLoader.load(from: catalogURL)

            if let loadedRegistry = result.registry {
                caps.merge(loadedRegistry.capabilitiesByID) { _, disk in disk }
                bundles.merge(loadedRegistry.bundlesByID) { _, disk in disk }
                units.merge(loadedRegistry.runtimeUnitsByID) { _, disk in disk }
            }
            diskWarnings = result.issues.filter { !$0.isError }
            let diskErrors = result.issues.filter { $0.isError }
            for err in diskErrors {
                log.error("  \(err.description)")
            }
        } else if path != NSString(string: HavenSettingsModel.defaultCatalogFolder).expandingTildeInPath {
            // Only warn if user explicitly configured a non-default folder that's missing
            log.warning("Catalog folder not found: \(path)")
        }

        let merged = SpecRegistry(
            capabilitiesByID: caps,
            bundlesByID: bundles,
            runtimeUnitsByID: units
        )
        self.registry = merged

        // Build catalog entries from the merged registry for UI display
        let bundlesByCap = Dictionary(
            grouping: merged.bundlesByID.values, by: \.capability
        )
        catalog = merged.capabilitiesByID.values.compactMap { cap in
            guard let bundle = bundlesByCap[cap.id]?.first else {
                log.warning("No bundle for capability \(cap.id), skipping")
                return nil
            }
            let meta = CatalogMetadata(
                icon: cap.icon ?? "shippingbox",
                iconImagePath: cap.iconImage,
                notes: cap.notes,
                fullDescription: cap.fullDescription ?? cap.description ?? ""
            )
            return CatalogEntry(capability: cap, bundle: bundle, metadata: meta)
        }

        let counts = CatalogCounts(
            capabilities: merged.capabilitiesByID.count,
            bundles: merged.bundlesByID.count,
            runtimeUnits: merged.runtimeUnitsByID.count
        )

        if diskWarnings.isEmpty {
            catalogState = .loaded(counts: counts)
        } else {
            for warning in diskWarnings {
                log.warning("  \(warning.description)")
            }
            catalogState = .loadedWithWarnings(counts: counts, warnings: diskWarnings)
        }
        log.info("Catalog loaded: \(counts.capabilities) capabilities, \(counts.bundles) bundles, \(counts.runtimeUnits) runtime units")
    }

    // MARK: - State Loading

    private func loadInstalledState() {
        do {
            havenState = try stateStore.load()
            log.info("Loaded state: \(self.havenState.services.count) installed services")
            for (id, svc) in havenState.services {
                log.debug("  \(id): status=\(svc.status.rawValue), units=\(svc.runtimeUnits)")
            }
        } catch {
            log.error("State file incompatible: \(error.localizedDescription) — backing up and resetting")
            let fm = FileManager.default
            let stateFile = paths.stateFile
            if fm.fileExists(atPath: stateFile.path) {
                let backup = stateFile.deletingLastPathComponent()
                    .appendingPathComponent("services.backup.json")
                try? fm.removeItem(at: backup)
                try? fm.moveItem(at: stateFile, to: backup)
            }
            havenState = HavenState()
            try? stateStore.save(havenState)
        }
    }

    // MARK: - View Model Building

    private func rebuildViewModels() {
        let installedCapIDs = Set(havenState.services.keys)

        // Remove facades for uninstalled services
        for key in facades.keys where !installedCapIDs.contains(key) {
            facades.removeValue(forKey: key)
        }

        // Build installed services from persisted state FIRST,
        // so facade.refresh() reads current status (not stale data).
        installedServices = havenState.services.values.sorted(by: { $0.capability < $1.capability }).map { stored in
            let entry = catalog.first { $0.capability.id == stored.capability }
            let meta = entry?.metadata ?? CatalogEntry.defaultMetadata
            let port = stored.portAssignments.first?.port

            return InstalledService(
                id: stored.capability,
                name: entry?.capability.name ?? Self.displayName(from: stored.capability),
                serviceDescription: entry?.capability.description ?? "",
                icon: meta.icon,
                iconImagePath: meta.iconImagePath,
                status: mapStatus(stored.status),
                port: port,
                dataPath: stored.directoryLayout.data.path,
                instructions: entry?.bundle.instructions,
                onboarding: stored.onboarding
            )
        }

        // Refresh existing facades (after installedServices is current)
        for facade in facades.values {
            facade.refresh()
        }

        // Build discoverable plugins from catalog
        discoverablePlugins = catalog.map { entry in
            DiscoverablePlugin(
                id: entry.capability.id,
                name: entry.capability.name,
                summary: entry.capability.description ?? "",
                icon: entry.metadata.icon,
                iconImagePath: entry.metadata.iconImagePath,
                notes: entry.metadata.notes,
                isInstalled: installedCapIDs.contains(entry.capability.id),
                fullDescription: entry.metadata.fullDescription,
                screenshotPaths: entry.capability.screenshots
            )
        }
    }

    // MARK: - Helpers

    /// Derive a human-readable name from a capability ID.
    /// e.g. "haven.capability.hello-service" → "Hello Service"
    private static func displayName(from capabilityID: String) -> String {
        let slug = capabilityID.split(separator: ".").last.map(String.init) ?? capabilityID
        return slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    // MARK: - Status Mapping

    private func mapStatus(_ coreStatus: HavenCore.ServiceStatus) -> ServiceStatus {
        switch coreStatus {
        case .installed: .stopped
        case .running:   .running
        case .stopped:   .stopped
        case .failed:    .failed
        }
    }
}

// MARK: - Catalog Entry

/// A capability paired with its bundle and UI metadata, ready for display.
struct CatalogEntry: Identifiable {
    let capability: Capability
    let bundle: HavenCore.Bundle
    let metadata: CatalogMetadata

    var id: String { capability.id }
}

/// UI metadata derived from capability spec fields.
struct CatalogMetadata {
    let icon: String
    let iconImagePath: String?
    let notes: [String]
    let fullDescription: String
}

extension CatalogEntry {
    /// Fallback metadata for capabilities without a catalog entry.
    static let defaultMetadata = CatalogMetadata(
        icon: "shippingbox",
        iconImagePath: nil,
        notes: [],
        fullDescription: ""
    )
}

