import Foundation
import HavenCore

/// Prepares Haven-managed Python applications for launch.
///
/// The Python adapter models a fully Haven-managed Python environment.
/// Users never install Python packages manually — Haven provisions a
/// virtual environment per service unit, installs dependencies, and
/// produces a launch command that uses the venv's interpreter.
///
/// ## Directory layout under the service root
///
/// ```
/// run/
///   venvs/<unit-id>/          ← per-unit virtual environment
///     bin/python3             ← the interpreter to launch with
///     lib/                    ← installed packages
/// ```
///
/// ## Current phase
///
/// This adapter computes deterministic paths and launch commands.
/// Actual venv creation and package installation are deferred to the
/// execution layer (not yet implemented).
public struct PythonRuntimeAdapter: RuntimeAdapter {

    public let runtimeType: RuntimeUnit.RuntimeType = .python

    public init() {}

    public func prepare(
        unit: RuntimeUnit,
        plannedUnit: PlannedRuntimeUnit,
        serviceLayout: ServiceDirectoryLayout
    ) throws -> PreparedRuntime {
        // Validate install source is present
        let source = unit.installSource.trimmingCharacters(in: .whitespaces)
        guard !source.isEmpty else {
            throw RuntimeAdapterError.missingInstallSource(unitID: unit.id)
        }

        // Validate launch arguments are present
        guard !plannedUnit.resolvedLaunchArguments.isEmpty else {
            throw RuntimeAdapterError.missingLaunchArguments(unitID: unit.id)
        }

        // Compute the venv root for this unit
        let venvRoot = venvDirectory(for: unit.id, serviceLayout: serviceLayout)
        let pythonExecutable = venvRoot
            .appendingPathComponent("bin")
            .appendingPathComponent("python3")

        // Arguments are the resolved launch arguments (script/module path and flags).
        // The executable (venv python) is conveyed via executableURL —
        // LaunchdJob.make() will prepend it to ProgramArguments.
        let arguments = plannedUnit.resolvedLaunchArguments

        // Build the environment. The venv's bin directory is prepended to PATH
        // so that any subprocess spawned by the Python app also uses the venv.
        var environment = plannedUnit.resolvedEnvironment
        let venvBin = venvRoot.appendingPathComponent("bin").path
        environment["VIRTUAL_ENV"] = venvRoot.path
        environment["PATH"] = "\(venvBin):/usr/bin:/bin"

        // Managed directories: the venv root must exist before launch.
        var managedDirs = serviceLayout.allDirectories
        managedDirs.append(venvRoot)

        return PreparedRuntime(
            unitID: unit.id,
            executableURL: pythonExecutable,
            arguments: arguments,
            environment: environment,
            workingDirectory: serviceLayout.serviceRoot,
            managedDirectories: managedDirs,
            runtimeType: .python,
            healthcheck: plannedUnit.resolvedHealthcheck,
            port: plannedUnit.port?.number,
            dependsOn: plannedUnit.dependsOn
        )
    }

    public func teardown(
        preparedRuntime: PreparedRuntime,
        serviceLayout: ServiceDirectoryLayout
    ) throws {
        // Python teardown would remove the venv directory.
        // Actual filesystem deletion is deferred to the execution layer.
    }

    // MARK: - Path helpers

    /// The virtual environment directory for a given unit ID.
    ///
    /// Layout: `<serviceRoot>/run/venvs/<unit-id>/`
    public func venvDirectory(
        for unitID: String,
        serviceLayout: ServiceDirectoryLayout
    ) -> URL {
        serviceLayout.run
            .appendingPathComponent("venvs")
            .appendingPathComponent(unitID)
    }
}
