import Foundation
import HavenCore
import HavenRuntimes
import HavenLaunchd

/// MVP end-to-end executor that orchestrates the full service lifecycle.
///
/// Wires together spec loading, planning, runtime preparation, launchd job
/// management, and state persistence into a single API surface.
///
/// ## Supported operations
///
/// - `install` — plan, prepare runtimes, install launchd jobs, persist state
/// - `uninstall` — stop jobs, remove plists, remove state
/// - `start` / `stop` — control running state via launchd
/// - `status` — combine persisted state with live launchd status
public struct HavenExecutor: Sendable {

    private let paths: HavenPaths
    private let stateStore: any StateStore
    private let runtimeRegistry: RuntimeAdapterRegistry
    private let launchdController: LaunchdController
    private let fileManager: FileManager

    public init(
        paths: HavenPaths,
        stateStore: any StateStore,
        runtimeRegistry: RuntimeAdapterRegistry = .makeDefault(),
        launchdController: LaunchdController,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.stateStore = stateStore
        self.runtimeRegistry = runtimeRegistry
        self.launchdController = launchdController
        self.fileManager = fileManager
    }

    // MARK: - Install

    /// Install a capability: plan, prepare runtimes, register launchd jobs, persist state.
    ///
    /// Does not start the services. Call `start(capabilityID:)` afterwards if desired.
    ///
    /// - Parameters:
    ///   - capabilityID: The capability to install.
    ///   - registry: The spec registry containing capabilities, bundles, and runtime units.
    ///   - settings: User-provided settings (key-value pairs).
    /// - Returns: The persisted service state.
    public func install(
        capabilityID: String,
        registry: SpecRegistry,
        settings: [String: String] = [:]
    ) throws -> StoredServiceState {
        // 1. Guard not already installed
        if let _ = try stateStore.service(for: capabilityID) {
            throw ExecutorError.alreadyInstalled(capabilityID: capabilityID)
        }

        // 2. Plan
        let plan: InstallPlan
        do {
            plan = try Planner.planInstall(
                capabilityID: capabilityID,
                registry: registry,
                settings: settings,
                baseDirectory: paths.base
            )
        } catch {
            throw ExecutorError.planningFailed(
                capabilityID: capabilityID,
                detail: error.localizedDescription
            )
        }

        let service = plan.service
        let serviceLayout = paths.serviceLayout(for: capabilityID)

        // 3. Create directories
        for dir in paths.topLevelDirectories + serviceLayout.allDirectories {
            try? fileManager.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }

        // 4. Prepare runtimes and install launchd jobs for each unit
        for plannedUnit in service.units {
            let unit = plannedUnit.spec

            // Prepare runtime
            let prepared: PreparedRuntime
            do {
                prepared = try runtimeRegistry.prepare(
                    unit: unit,
                    plannedUnit: plannedUnit,
                    serviceLayout: serviceLayout
                )
            } catch {
                throw ExecutorError.preparationFailed(
                    capabilityID: capabilityID,
                    unitID: unit.id,
                    detail: error.localizedDescription
                )
            }

            // Build and install launchd job
            let job = LaunchdJob.make(
                capabilityID: capabilityID,
                unitID: unit.id,
                preparedRuntime: prepared,
                serviceLayout: serviceLayout
            )

            do {
                try launchdController.install(job: job)
            } catch {
                throw ExecutorError.serviceInstallFailed(
                    capabilityID: capabilityID,
                    unitID: unit.id,
                    detail: error.localizedDescription
                )
            }
        }

        // 5. Build and persist state
        let now = Date()
        let portAssignments = service.units.compactMap { unit -> StoredPortAssignment? in
            guard let port = unit.port else { return nil }
            return StoredPortAssignment(unitID: unit.spec.id, port: port.number)
        }

        let storedState = StoredServiceState(
            capabilityID: capabilityID,
            bundleID: service.bundle.id,
            installedAt: now,
            updatedAt: now,
            status: .installed,
            resolvedSettings: service.resolvedSettings,
            portAssignments: portAssignments,
            runtimeUnitIDs: service.units.map(\.spec.id),
            directoryLayout: serviceLayout
        )

        try stateStore.upsert(storedState)
        return storedState
    }

    // MARK: - Uninstall

    /// Uninstall a capability: stop jobs, remove plists, remove state, clean up directories.
    public func uninstall(capabilityID: String) throws {
        guard let service = try stateStore.service(for: capabilityID) else {
            throw ExecutorError.notInstalled(capabilityID: capabilityID)
        }

        // Stop and uninstall launchd jobs in reverse dependency order
        for unitID in service.runtimeUnitIDs.reversed() {
            let label = LaunchdLabel.label(
                capabilityID: capabilityID,
                unitID: unitID
            )
            // Best-effort stop
            try? launchdController.stop(label: label)

            do {
                try launchdController.uninstall(label: label)
            } catch {
                throw ExecutorError.serviceUninstallFailed(
                    capabilityID: capabilityID,
                    unitID: unitID,
                    detail: error.localizedDescription
                )
            }
        }

        // Remove state
        try stateStore.remove(capabilityID: capabilityID)

        // Best-effort remove service directory
        try? fileManager.removeItem(at: service.directoryLayout.serviceRoot)
    }

    // MARK: - Start

    /// Start all units for an installed service, in dependency order.
    public func start(capabilityID: String) throws {
        guard var service = try stateStore.service(for: capabilityID) else {
            throw ExecutorError.notInstalled(capabilityID: capabilityID)
        }

        for unitID in service.runtimeUnitIDs {
            let label = LaunchdLabel.label(
                capabilityID: capabilityID,
                unitID: unitID
            )
            do {
                try launchdController.start(label: label)
            } catch {
                throw ExecutorError.startFailed(
                    capabilityID: capabilityID,
                    unitID: unitID,
                    detail: error.localizedDescription
                )
            }
        }

        service.status = .running
        service.updatedAt = Date()
        try stateStore.upsert(service)
    }

    // MARK: - Stop

    /// Stop all units for a running service, in reverse dependency order.
    public func stop(capabilityID: String) throws {
        guard var service = try stateStore.service(for: capabilityID) else {
            throw ExecutorError.notInstalled(capabilityID: capabilityID)
        }

        for unitID in service.runtimeUnitIDs.reversed() {
            let label = LaunchdLabel.label(
                capabilityID: capabilityID,
                unitID: unitID
            )
            do {
                try launchdController.stop(label: label)
            } catch {
                throw ExecutorError.stopFailed(
                    capabilityID: capabilityID,
                    unitID: unitID,
                    detail: error.localizedDescription
                )
            }
        }

        service.status = .stopped
        service.updatedAt = Date()
        try stateStore.upsert(service)
    }

    // MARK: - Status

    /// Query the current status of an installed service.
    ///
    /// Combines persisted state with live launchd status for each unit.
    public func status(capabilityID: String) throws -> ServiceStatusReport {
        guard let service = try stateStore.service(for: capabilityID) else {
            throw ExecutorError.notInstalled(capabilityID: capabilityID)
        }

        var unitStatuses: [UnitStatusReport] = []
        for unitID in service.runtimeUnitIDs {
            let label = LaunchdLabel.label(
                capabilityID: capabilityID,
                unitID: unitID
            )
            let jobStatus: LaunchdJobStatus
            do {
                jobStatus = try launchdController.status(label: label)
            } catch {
                throw ExecutorError.statusQueryFailed(
                    capabilityID: capabilityID,
                    detail: error.localizedDescription
                )
            }
            unitStatuses.append(UnitStatusReport(
                unitID: unitID,
                launchdLabel: label,
                state: jobStatus.state,
                pid: jobStatus.pid,
                lastExitStatus: jobStatus.lastExitStatus
            ))
        }

        return ServiceStatusReport(
            capabilityID: capabilityID,
            bundleID: service.bundleID,
            status: service.status,
            unitStatuses: unitStatuses
        )
    }
}
