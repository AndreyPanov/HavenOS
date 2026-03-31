import Foundation
import HavenCore

/// Prepares native macOS binaries for launch.
///
/// The native adapter assumes Haven has already placed the executable
/// at the `installSource` path. It validates the path, resolves
/// arguments and environment from the planned unit, and produces a
/// `PreparedRuntime` ready for the execution layer.
///
/// No process execution happens here — this is pure preparation.
public struct NativeRuntimeAdapter: RuntimeAdapter {

    public let runtimeType: RuntimeUnit.RuntimeType = .native

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

        // Resolve the executable — if installSource is a directory, find
        // the actual executable inside it.
        let executableURL = try NativeRuntimeAdapter.resolveExecutable(
            at: source, unitID: unit.id
        )

        // Strip the executable path from arguments if it was included as
        // argv[0] (legacy spec convention). The executable is conveyed
        // separately via executableURL; LaunchdJob.make() will prepend it.
        var args = plannedUnit.resolvedLaunchArguments
        if let first = args.first, first == executableURL.path {
            args.removeFirst()
        }

        return PreparedRuntime(
            unitID: unit.id,
            executableURL: executableURL,
            arguments: args,
            environment: plannedUnit.resolvedEnvironment,
            workingDirectory: serviceLayout.serviceRoot,
            managedDirectories: serviceLayout.allDirectories,
            runtimeType: .native,
            healthcheck: plannedUnit.resolvedHealthcheck,
            port: plannedUnit.port?.number,
            dependsOn: plannedUnit.dependsOn
        )
    }

    // MARK: - Executable resolution

    /// Resolve an install source path to an actual executable URL.
    ///
    /// - If the path is a regular file, use it directly.
    /// - If the path is a directory, find the first executable file inside.
    /// - Otherwise, fall back to treating the path as-is (for specs
    ///   referencing executables that don't exist yet).
    static func resolveExecutable(at path: String, unitID: String) throws -> URL {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            // Path doesn't exist yet (e.g. before artifact installation).
            // Return it as-is — the execution layer will fail later with
            // a clear error if the binary is truly missing.
            return URL(fileURLWithPath: path)
        }

        if !isDir.boolValue {
            // It's a file — use it directly.
            return URL(fileURLWithPath: path)
        }

        // It's a directory — find the executable inside.
        guard let contents = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: nil
        ) else {
            throw RuntimeAdapterError.executableNotFound(unitID: unitID, path: path)
        }

        let executables = contents.filter { url in
            var fileIsDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &fileIsDir)
                && !fileIsDir.boolValue
                && fm.isExecutableFile(atPath: url.path)
        }

        guard let executable = executables.first else {
            throw RuntimeAdapterError.executableNotFound(unitID: unitID, path: path)
        }

        return executable
    }

    public func teardown(
        preparedRuntime: PreparedRuntime,
        serviceLayout: ServiceDirectoryLayout
    ) throws {
        // Native binaries have no runtime-specific teardown beyond
        // removing the service directory tree, which is handled by
        // the service manager. This is intentionally a no-op.
    }
}
