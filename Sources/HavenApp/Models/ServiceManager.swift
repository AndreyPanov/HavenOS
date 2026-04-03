import Foundation
import HavenCore
import HavenExecutor
import HavenRuntimes
import HavenLaunchd
import HavenInstaller
import SwiftUI

/// Central data layer that bridges HavenCore specs and state to the UI.
///
/// - Discovery: Loads `Capability` + `Bundle` + `RuntimeUnit` from bundled JSON resources
/// - Installed: Reads `HavenState` from `FileStateStore` at `~/.haven/`
/// - Lifecycle: Delegates install/uninstall/start/stop to `HavenExecutor`
@MainActor
@Observable
final class ServiceManager {

    // MARK: - Published Data

    /// Services currently installed (from ~/.haven/State/services.json).
    private(set) var installedServices: [InstalledService] = []

    /// All discoverable plugins (from bundled catalog specs).
    private(set) var discoverablePlugins: [DiscoverablePlugin] = []

    // MARK: - UI State

    /// True while an install/uninstall/start/stop operation is in progress.
    private(set) var isPerformingAction = false

    /// Description of the last error, cleared on next action.
    var lastError: String?

    // MARK: - Internal State

    private var catalog: [CatalogEntry] = []
    private var runtimeUnits: [RuntimeUnit] = []
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
    }

    // MARK: - Loading

    /// Load catalog and installed state. Call once on app launch.
    func load() {
        loadCatalog()
        loadInstalledState()
        rebuildViewModels()
    }

    /// Reload just the installed state (e.g. on timer or after an action).
    func refresh() {
        loadInstalledState()
        rebuildViewModels()
    }

    // MARK: - Lifecycle Actions

    /// Install a service by capability ID. Runs the executor on a background thread.
    func installService(capabilityID: String) async {
        isPerformingAction = true
        lastError = nil

        let registry = buildRegistry()
        let executor = self.executor

        do {
            _ = try await Task.detached {
                try executor.install(capabilityID: capabilityID, registry: registry)
            }.value
            refresh()
        } catch {
            lastError = error.localizedDescription
        }

        isPerformingAction = false
    }

    /// Uninstall a service by capability ID.
    func uninstallService(capabilityID: String) async {
        isPerformingAction = true
        lastError = nil

        let executor = self.executor

        do {
            try await Task.detached {
                try executor.uninstall(capabilityID: capabilityID)
            }.value
            refresh()
        } catch {
            lastError = error.localizedDescription
        }

        isPerformingAction = false
    }

    /// Start an installed service.
    func startService(capabilityID: String) async {
        isPerformingAction = true
        lastError = nil

        let executor = self.executor

        do {
            try await Task.detached {
                try executor.start(capabilityID: capabilityID)
            }.value
            refresh()
        } catch {
            lastError = error.localizedDescription
        }

        isPerformingAction = false
    }

    /// Stop a running service.
    func stopService(capabilityID: String) async {
        isPerformingAction = true
        lastError = nil

        let executor = self.executor

        do {
            try await Task.detached {
                try executor.stop(capabilityID: capabilityID)
            }.value
            refresh()
        } catch {
            lastError = error.localizedDescription
        }

        isPerformingAction = false
    }

    // MARK: - Catalog Loading

    private func loadCatalog() {
        guard let catalogURL = Foundation.Bundle.module.url(forResource: "Catalog", withExtension: nil) else {
            return
        }
        let capabilitiesURL = catalogURL.appendingPathComponent("Capabilities")
        let bundlesURL = catalogURL.appendingPathComponent("Bundles")
        let runtimeURL = catalogURL.appendingPathComponent("Runtime")

        let capabilities = decodeAll(Capability.self, from: capabilitiesURL)
        let bundles = decodeAll(HavenCore.Bundle.self, from: bundlesURL)
        runtimeUnits = decodeAll(RuntimeUnit.self, from: runtimeURL)

        // Pair each capability with its implementing bundle
        let bundlesByCap = Dictionary(grouping: bundles, by: \.capability)

        catalog = capabilities.compactMap { cap in
            guard let bundle = bundlesByCap[cap.id]?.first else { return nil }
            let meta = CatalogEntry.knownMetadata[cap.id] ?? CatalogEntry.defaultMetadata
            return CatalogEntry(capability: cap, bundle: bundle, metadata: meta)
        }
    }

    /// Decode all JSON files of a given Codable type from a directory.
    private func decodeAll<T: Decodable>(_ type: T.Type, from directory: URL) -> [T] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(T.self, from: data)
            }
    }

    // MARK: - State Loading

    private func loadInstalledState() {
        havenState = (try? stateStore.load()) ?? HavenState()
    }

    // MARK: - Registry Building

    /// Build a `SpecRegistry` from the loaded catalog and runtime units
    /// for use by the executor.
    private func buildRegistry() -> SpecRegistry {
        var capsByID: [String: Capability] = [:]
        var bundlesByID: [String: HavenCore.Bundle] = [:]
        var unitsByID: [String: RuntimeUnit] = [:]

        for entry in catalog {
            capsByID[entry.capability.id] = entry.capability
            bundlesByID[entry.bundle.id] = entry.bundle
        }
        for unit in runtimeUnits {
            unitsByID[unit.id] = unit
        }

        return SpecRegistry(
            capabilitiesByID: capsByID,
            bundlesByID: bundlesByID,
            runtimeUnitsByID: unitsByID
        )
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
                name: entry?.capability.name ?? stored.capability,
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

    // MARK: - Status Mapping

    /// Maps HavenCore.ServiceStatus to the app's ServiceStatus.
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
