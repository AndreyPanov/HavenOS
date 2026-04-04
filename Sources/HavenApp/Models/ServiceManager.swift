import Foundation
import HavenCore
import HavenExecutor
import HavenRuntimes
import HavenLaunchd
import HavenInstaller
import SwiftUI
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
    /// Catalog loaded successfully.
    case loaded(counts: CatalogCounts)
    /// Catalog folder does not exist at the configured path.
    case folderNotFound(path: String)
    /// Catalog loaded but SpecLoader reported validation issues.
    case issues([SpecLoadIssue])
}

/// Central data layer that bridges HavenCore specs and state to the UI.
///
/// - Discovery: Loads specs from a local folder via `SpecLoader`
/// - Installed: Reads `HavenState` from `FileStateStore` at `~/.haven/`
/// - Lifecycle: Delegates install/uninstall/start/stop to `HavenExecutor`
@MainActor
@Observable
final class ServiceManager {

    // MARK: - Published Data

    /// Services currently installed (from ~/.haven/State/services.json).
    private(set) var installedServices: [InstalledService] = []

    /// All discoverable plugins (from local catalog specs).
    private(set) var discoverablePlugins: [DiscoverablePlugin] = []

    // MARK: - UI State

    /// True while an install/uninstall/start/stop operation is in progress.
    private(set) var isPerformingAction = false

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

    // MARK: - Init

    init(basePath: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".haven")) {
        self.paths = HavenPaths(base: basePath)
        self.stateStore = FileStateStore(paths: paths)
        self.executor = HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: LaunchdController(),
            artifactInstaller: ArtifactInstaller(paths: paths)
        )
        log.info("Initialized with base path: \(basePath.path)")
    }

    // MARK: - Loading

    /// Load catalog from the given URL and installed state. Call once on app launch.
    func load(catalogURL: URL) {
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
        log.info("Installing service: \(capabilityID)")
        isPerformingAction = true
        lastError = nil

        guard let registry = self.registry else {
            lastError = "No catalog loaded. Configure your catalog folder in Settings."
            isPerformingAction = false
            return
        }

        let executor = self.executor

        do {
            _ = try await Task.detached {
                try executor.install(capabilityID: capabilityID, registry: registry)
            }.value
            log.info("Install succeeded: \(capabilityID)")
            refresh()
        } catch {
            log.error("Install failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        isPerformingAction = false
    }

    /// Uninstall a service by capability ID.
    func uninstallService(capabilityID: String) async {
        log.info("Uninstalling service: \(capabilityID)")
        isPerformingAction = true
        lastError = nil

        let executor = self.executor

        do {
            try await Task.detached {
                try executor.uninstall(capabilityID: capabilityID)
            }.value
            log.info("Uninstall succeeded: \(capabilityID)")
            refresh()
        } catch {
            log.error("Uninstall failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        isPerformingAction = false
    }

    /// Start an installed service.
    func startService(capabilityID: String) async {
        log.info("Starting service: \(capabilityID)")
        isPerformingAction = true
        lastError = nil

        let executor = self.executor

        do {
            try await Task.detached {
                try executor.start(capabilityID: capabilityID)
            }.value
            log.info("Start succeeded: \(capabilityID)")
            refresh()
        } catch {
            log.error("Start failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        isPerformingAction = false
    }

    /// Stop a running service.
    func stopService(capabilityID: String) async {
        log.info("Stopping service: \(capabilityID)")
        isPerformingAction = true
        lastError = nil

        let executor = self.executor

        do {
            try await Task.detached {
                try executor.stop(capabilityID: capabilityID)
            }.value
            log.info("Stop succeeded: \(capabilityID)")
            refresh()
        } catch {
            log.error("Stop failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        isPerformingAction = false
    }

    // MARK: - Catalog Folder Setup

    /// Ensure the catalog folder and its expected subdirectories exist.
    private func ensureCatalogFolderExists(at url: URL) {
        let fm = FileManager.default
        let subdirs = ["Capabilities", "Bundles", "Runtime"]

        if !fm.fileExists(atPath: url.path) {
            log.info("Creating default catalog folder at: \(url.path)")
            do {
                for subdir in subdirs {
                    try fm.createDirectory(
                        at: url.appendingPathComponent(subdir),
                        withIntermediateDirectories: true
                    )
                }
                log.info("Created catalog folder with subdirectories: \(subdirs.joined(separator: ", "))")
            } catch {
                log.error("Failed to create catalog folder: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Catalog Loading

    private func loadCatalog(from catalogURL: URL) {
        let fm = FileManager.default
        let path = catalogURL.path

        guard fm.fileExists(atPath: path) else {
            log.warning("Catalog folder not found: \(path)")
            catalogState = .folderNotFound(path: path)
            catalog = []
            registry = nil
            return
        }

        log.info("Loading catalog via SpecLoader from: \(path)")
        let result = SpecLoader.load(from: catalogURL)

        if let loadedRegistry = result.registry {
            self.registry = loadedRegistry

            // Build catalog entries from the registry for UI display
            let bundlesByCap = Dictionary(
                grouping: loadedRegistry.bundlesByID.values, by: \.capability
            )
            catalog = loadedRegistry.capabilitiesByID.values.compactMap { cap in
                guard let bundle = bundlesByCap[cap.id]?.first else {
                    log.warning("No bundle for capability \(cap.id), skipping")
                    return nil
                }
                let meta = CatalogEntry.knownMetadata[cap.id] ?? CatalogEntry.defaultMetadata
                return CatalogEntry(capability: cap, bundle: bundle, metadata: meta)
            }

            let counts = CatalogCounts(
                capabilities: loadedRegistry.capabilitiesByID.count,
                bundles: loadedRegistry.bundlesByID.count,
                runtimeUnits: loadedRegistry.runtimeUnitsByID.count
            )
            catalogState = .loaded(counts: counts)
            log.info("Catalog loaded: \(counts.capabilities) capabilities, \(counts.bundles) bundles, \(counts.runtimeUnits) runtime units")
        } else {
            log.error("Catalog loading failed with \(result.issues.count) issues")
            for issue in result.issues {
                log.error("  \(issue.description)")
            }
            catalogState = .issues(result.issues)
            catalog = []
            registry = nil
        }
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

        // Build installed services from persisted state
        installedServices = havenState.services.values.map { stored in
            let entry = catalog.first { $0.capability.id == stored.capability }
            let meta = entry?.metadata ?? CatalogEntry.defaultMetadata
            let port = stored.portAssignments.first?.port

            return InstalledService(
                id: stored.capability,
                name: entry?.capability.name ?? Self.displayName(from: stored.capability),
                serviceDescription: entry?.capability.description ?? "",
                icon: meta.icon,
                status: mapStatus(stored.status),
                port: port,
                dataPath: stored.directoryLayout.data.path
            )
        }

        // Build discoverable plugins from catalog
        discoverablePlugins = catalog.map { entry in
            DiscoverablePlugin(
                id: entry.capability.id,
                name: entry.capability.name,
                summary: entry.capability.description ?? "",
                icon: entry.metadata.icon,
                notes: entry.metadata.notes,
                isInstalled: installedCapIDs.contains(entry.capability.id),
                fullDescription: entry.metadata.fullDescription
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

/// UI metadata that HavenCore specs do not carry (icons, etc.).
struct CatalogMetadata {
    let icon: String
    let notes: [String]
    let fullDescription: String
}

extension CatalogEntry {
    /// UI metadata for known services, keyed by capability ID.
    static let knownMetadata: [String: CatalogMetadata] = [
        "haven.capability.hello-service": CatalogMetadata(
            icon: "hand.wave",
            notes: ["Lightweight", "Native service"],
            fullDescription: "Hello Service is a minimal service that responds to HTTP requests with a greeting. Useful for testing your Haven setup and verifying connectivity."
        ),
    ]

    /// Fallback metadata for capabilities without a known entry.
    static let defaultMetadata = CatalogMetadata(
        icon: "shippingbox",
        notes: [],
        fullDescription: ""
    )
}
