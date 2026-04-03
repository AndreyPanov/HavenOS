import Foundation
import HavenCore
import HavenRuntimes
import HavenLaunchd
import HavenInstaller
import os

private let log = Logger(subsystem: "com.haven", category: "Executor")

/// MVP end-to-end executor that orchestrates the full service lifecycle.
///
/// Wires together spec loading, planning, artifact installation, runtime
/// preparation, launchd job management, and state persistence into a single
/// API surface.
///
/// ## Supported operations
///
/// - `install` — plan, install artifacts, prepare runtimes, install launchd jobs, persist state
/// - `uninstall` — stop jobs, remove plists, remove artifacts, remove state
/// - `start` / `stop` — control running state via launchd
/// - `status` — combine persisted state with live launchd status
public struct HavenExecutor: Sendable {

    private let paths: HavenPaths
    private let stateStore: any StateStore
    private let runtimeRegistry: RuntimeAdapterRegistry
    private let launchdController: LaunchdController
    private let artifactInstaller: ArtifactInstaller?
    private nonisolated(unsafe) let fileManager: FileManager

    public init(
        paths: HavenPaths,
        stateStore: any StateStore,
        runtimeRegistry: RuntimeAdapterRegistry = .makeDefault(),
        launchdController: LaunchdController,
        artifactInstaller: ArtifactInstaller? = nil,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.stateStore = stateStore
        self.runtimeRegistry = runtimeRegistry
        self.launchdController = launchdController
        self.artifactInstaller = artifactInstaller
        self.fileManager = fileManager
    }

    // MARK: - Install

    /// Install a capability: plan, install artifacts, prepare runtimes, register
    /// launchd jobs, persist state.
    ///
    /// On failure, any work completed during this attempt is rolled back on a
    /// best-effort basis (installed jobs unloaded, artifacts removed, state entry
    /// deleted, service directory removed). The original error is always preserved
    /// as the thrown result.
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
        log.info("[install] Starting install for \(capabilityID)")

        // 1. Guard not already installed
        if let _ = try stateStore.service(for: capabilityID) {
            throw ExecutorError.alreadyInstalled(capabilityID: capabilityID)
        }

        // 2. Plan
        log.info("[install] Planning...")
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
        log.info("[install] Plan OK: bundle=\(service.bundle.id), units=\(service.units.count), serviceRoot=\(serviceLayout.serviceRoot.path)")

        // Rollback stack: closures executed in reverse on failure.
        // Each step that creates side effects registers a cleanup closure.
        var rollbackActions: [() -> Void] = []

        /// Run all registered rollback actions in reverse order, then throw
        /// the original error. Cleanup failures are silently ignored.
        func rollback(_ error: Error) throws -> Never {
            for action in rollbackActions.reversed() {
                action()
            }
            throw error
        }

        // 3. Create directories
        log.debug("[install] Creating directories...")
        for dir in paths.topLevelDirectories + serviceLayout.allDirectories {
            try? fileManager.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }

        // Register service directory cleanup (only the service-specific tree)
        rollbackActions.append { [fileManager] in
            try? fileManager.removeItem(at: serviceLayout.serviceRoot)
        }

        // 4. Install artifacts and prepare runtimes, then install launchd jobs
        for plannedUnit in service.units {
            let unit = plannedUnit.spec
            log.info("[install] Processing unit \(unit.id) (runtime=\(unit.runtimeType.rawValue), source=\(unit.installSource))")

            // Reject unsupported runtime types
            if unit.runtimeType == .python {
                try rollback(ExecutorError.unsupportedRuntime(
                    capabilityID: capabilityID,
                    unitID: unit.id,
                    detail: "This service requires a runtime that is not yet available in Haven."
                ))
            }

            // Install artifact if an installer is configured
            let resolvedUnit: RuntimeUnit
            if let installer = artifactInstaller {
                let source = ArtifactSource(string: unit.installSource)
                let format = ArtifactFormat.detect(from: unit.installSource) ?? .executable
                log.info("[install] Installing artifact: source=\(unit.installSource), format=\(String(describing: format))")
                let descriptor = ArtifactDescriptor(
                    unitID: unit.id,
                    source: source,
                    format: format
                )

                let installResult: ArtifactInstallResult
                do {
                    installResult = try installer.install(descriptor: descriptor)
                    log.info("[install] Artifact installed: dir=\(installResult.installDirectory.path), cached=\(installResult.wasCached)")
                } catch {
                    try rollback(ExecutorError.artifactInstallFailed(
                        capabilityID: capabilityID,
                        unitID: unit.id,
                        detail: error.localizedDescription
                    ))
                }

                // Register artifact cleanup
                let unitIDForCleanup = unit.id
                rollbackActions.append {
                    try? installer.uninstall(unitID: unitIDForCleanup)
                }

                // Resolve installed executable path:
                // For executables: <installDir>/<original-filename>
                // For archives: <installDir>/<original-filename>
                let filename = URL(fileURLWithPath: unit.installSource).lastPathComponent
                let installedPath = installResult.installDirectory
                    .appendingPathComponent(filename).path

                // Create a unit with the resolved install source
                resolvedUnit = unit.withInstallSource(installedPath)
                log.info("[install] Resolved unit path: \(installedPath)")
            } else {
                resolvedUnit = unit
            }

            // Prepare runtime
            log.info("[install] Preparing runtime for unit \(unit.id)...")
            let prepared: PreparedRuntime
            do {
                prepared = try runtimeRegistry.prepare(
                    unit: resolvedUnit,
                    plannedUnit: plannedUnit,
                    serviceLayout: serviceLayout
                )
                log.info("[install] Runtime prepared: executable=\(prepared.executableURL.path)")
            } catch {
                try rollback(ExecutorError.preparationFailed(
                    capabilityID: capabilityID,
                    unitID: unit.id,
                    detail: error.localizedDescription
                ))
            }

            // Build and install launchd job
            let job = LaunchdJob.make(
                capabilityID: capabilityID,
                unitID: unit.id,
                preparedRuntime: prepared,
                serviceLayout: serviceLayout
            )
            log.info("[install] Installing launchd job: label=\(job.label)")

            do {
                try launchdController.install(job: job)
                log.info("[install] Launchd job installed: \(job.label)")
            } catch {
                try rollback(ExecutorError.serviceInstallFailed(
                    capabilityID: capabilityID,
                    unitID: unit.id,
                    detail: error.localizedDescription
                ))
            }

            // Register launchd job cleanup
            let label = LaunchdLabel.label(
                capabilityID: capabilityID,
                unitID: unit.id
            )
            rollbackActions.append { [launchdController] in
                try? launchdController.uninstall(label: label)
            }
        }

        // 5. Build and persist state
        log.info("[install] Persisting state for \(capabilityID)...")
        let now = Date()
        let portAssignments = service.units.compactMap { unit -> StoredPortAssignment? in
            guard let port = unit.port else { return nil }
            return StoredPortAssignment(unitID: unit.spec.id, port: port.number)
        }

        let storedState = StoredServiceState(
            capability: capabilityID,
            bundleID: service.bundle.id,
            installedAt: now,
            updatedAt: now,
            status: .installed,
            resolvedSettings: service.resolvedSettings,
            portAssignments: portAssignments,
            runtimeUnits: service.units.map(\.spec.id),
            directoryLayout: serviceLayout
        )

        do {
            try stateStore.upsert(storedState)
            log.info("[install] State persisted. Install complete for \(capabilityID)")
        } catch {
            try rollback(error)
        }

        return storedState
    }

    // MARK: - Uninstall

    /// Uninstall a capability: stop jobs, remove plists, remove artifacts, remove state,
    /// clean up directories.
    public func uninstall(capabilityID: String) throws {
        log.info("[uninstall] Starting uninstall for \(capabilityID)")
        guard let service = try stateStore.service(for: capabilityID) else {
            throw ExecutorError.notInstalled(capabilityID: capabilityID)
        }

        // Stop and uninstall launchd jobs in reverse dependency order
        for unitID in service.runtimeUnits.reversed() {
            let label = LaunchdLabel.label(
                capabilityID: capabilityID,
                unitID: unitID
            )
            log.info("[uninstall] Stopping and removing launchd job: \(label)")
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

        // Best-effort remove installed artifacts
        if let installer = artifactInstaller {
            for unitID in service.runtimeUnits {
                log.info("[uninstall] Removing artifact for unit: \(unitID)")
                try? installer.uninstall(unitID: unitID)
            }
        }

        // Remove state
        try stateStore.remove(capabilityID: capabilityID)
        log.info("[uninstall] State removed. Uninstall complete for \(capabilityID)")

        // Best-effort remove service directory
        try? fileManager.removeItem(at: service.directoryLayout.serviceRoot)
    }

    // MARK: - Start

    /// Start all units for an installed service, in dependency order.
    public func start(capabilityID: String) throws {
        log.info("[start] Starting service \(capabilityID)")
        guard var service = try stateStore.service(for: capabilityID) else {
            throw ExecutorError.notInstalled(capabilityID: capabilityID)
        }

        for unitID in service.runtimeUnits {
            let label = LaunchdLabel.label(
                capabilityID: capabilityID,
                unitID: unitID
            )
            log.info("[start] Starting launchd job: \(label)")
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
        log.info("[start] Service started: \(capabilityID)")
    }

    // MARK: - Stop

    /// Stop all units for a running service, in reverse dependency order.
    public func stop(capabilityID: String) throws {
        log.info("[stop] Stopping service \(capabilityID)")
        guard var service = try stateStore.service(for: capabilityID) else {
            throw ExecutorError.notInstalled(capabilityID: capabilityID)
        }

        for unitID in service.runtimeUnits.reversed() {
            let label = LaunchdLabel.label(
                capabilityID: capabilityID,
                unitID: unitID
            )
            log.info("[stop] Stopping launchd job: \(label)")
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
        log.info("[stop] Service stopped: \(capabilityID)")
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
        for unitID in service.runtimeUnits {
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
            capability: capabilityID,
            bundleID: service.bundleID,
            status: service.status,
            unitStatuses: unitStatuses
        )
    }
}
