import Foundation
import HavenCore

/// Prepares Haven-managed Python applications for launch.
///
/// The Python adapter models a fully Haven-managed Python environment.
/// Users never install Python packages manually — Haven provisions a
/// virtual environment per service unit, installs dependencies, and
/// produces a launch command that uses the venv's interpreter.
///
/// ## Directory layout
///
/// When `PythonConfig` is present (new path), the venv path is passed
/// via `installSource` by the executor after `PythonEnvironmentPreparer`
/// creates the environment at:
///
/// ```
/// ~/.haven/Installed/python/<unit-id>/venv/
/// ```
///
/// For legacy units (no PythonConfig), falls back to:
///
/// ```
/// <serviceRoot>/run/venvs/<unit-id>/
/// ```
public struct PythonRuntimeAdapter: RuntimeAdapter {

    public let runtimeType: RuntimeUnit.RuntimeType = .python

    public init() {}

    public func prepare(
        unit: RuntimeUnit,
        plannedUnit: PlannedRuntimeUnit,
        serviceLayout: ServiceDirectoryLayout
    ) throws -> PreparedRuntime {
        // Determine the venv root and launch arguments based on whether
        // a PythonConfig is present (new path) or not (legacy path).
        let venvRoot: URL
        let arguments: [String]

        if let pythonConfig = unit.python {
            // New path: PythonConfig-based unit.
            // The executor sets installSource to the venv directory path
            // after running PythonEnvironmentPreparer.
            let source = unit.installSource.trimmingCharacters(in: .whitespaces)
            if source.isEmpty {
                // installSource not yet resolved — compute from service layout
                // (used during planning/validation before executor runs)
                venvRoot = venvDirectory(for: unit.id, serviceLayout: serviceLayout)
            } else {
                venvRoot = URL(fileURLWithPath: source)
            }

            // Build: ["-m", "<module>"] + resolved args from spec
            var args = ["-m", pythonConfig.entrypoint.module]
            args.append(contentsOf: plannedUnit.resolvedLaunchArguments)
            arguments = args
        } else {
            // Legacy path: installSource-based Python unit.
            let source = unit.installSource.trimmingCharacters(in: .whitespaces)
            guard !source.isEmpty else {
                throw RuntimeAdapterError.missingInstallSource(unitID: unit.id)
            }
            guard !plannedUnit.resolvedLaunchArguments.isEmpty else {
                throw RuntimeAdapterError.missingLaunchArguments(unitID: unit.id)
            }
            venvRoot = venvDirectory(for: unit.id, serviceLayout: serviceLayout)
            arguments = plannedUnit.resolvedLaunchArguments
        }

        let pythonExecutable = venvRoot
            .appendingPathComponent("bin")
            .appendingPathComponent("python3")

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
