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

    /// Set after a successful install to trigger the post-install instructions sheet.
    var pendingInstructions: PendingInstructions?

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
            artifactInstaller: ArtifactInstaller(paths: paths),
            pythonPreparer: PythonEnvironmentPreparer()
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
        guard let registry = self.registry else {
            lastError = "No catalog loaded. Configure your catalog folder in Settings."
            return
        }
        await performAction("Install", capabilityID: capabilityID) { executor in
            _ = try executor.install(capabilityID: capabilityID, registry: registry)
        }

        // Show post-install instructions if the bundle provides them.
        if lastError == nil,
           let entry = catalog.first(where: { $0.capability.id == capabilityID }),
           let instructions = entry.bundle.instructions, !instructions.isEmpty
        {
            pendingInstructions = PendingInstructions(
                serviceName: entry.capability.name,
                instructions: instructions
            )
        }
    }

    /// Uninstall a service by capability ID.
    func uninstallService(capabilityID: String) async {
        await performAction("Uninstall", capabilityID: capabilityID) { executor in
            try executor.uninstall(capabilityID: capabilityID)
        }
    }

    /// Start an installed service.
    func startService(capabilityID: String) async {
        await performAction("Start", capabilityID: capabilityID) { executor in
            try executor.start(capabilityID: capabilityID)
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
                let meta = CatalogMetadata(
                    icon: cap.icon ?? "shippingbox",
                    iconImagePath: cap.iconImage,
                    notes: cap.notes,
                    fullDescription: cap.fullDescription ?? cap.description ?? ""
                )
                return CatalogEntry(capability: cap, bundle: bundle, metadata: meta)
            }

            let counts = CatalogCounts(
                capabilities: loadedRegistry.capabilitiesByID.count,
                bundles: loadedRegistry.bundlesByID.count,
                runtimeUnits: loadedRegistry.runtimeUnitsByID.count
            )

            let warnings = result.issues.filter { !$0.isError }
            if warnings.isEmpty {
                catalogState = .loaded(counts: counts)
            } else {
                for warning in warnings {
                    log.warning("  \(warning.description)")
                }
                catalogState = .loadedWithWarnings(counts: counts, warnings: warnings)
            }
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
                iconImagePath: meta.iconImagePath,
                status: mapStatus(stored.status),
                port: port,
                dataPath: stored.directoryLayout.data.path,
                instructions: entry?.bundle.instructions
            )
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

// MARK: - Post-Install Instructions

/// Transient state that triggers the post-install instructions sheet.
struct PendingInstructions: Identifiable {
    let id = UUID()
    let serviceName: String
    let instructions: String
}
