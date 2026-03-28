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

        let executableURL = URL(fileURLWithPath: source)

        return PreparedRuntime(
            unitID: unit.id,
            executableURL: executableURL,
            arguments: plannedUnit.resolvedLaunchArguments,
            environment: plannedUnit.resolvedEnvironment,
            workingDirectory: serviceLayout.serviceRoot,
            managedDirectories: serviceLayout.allDirectories,
            runtimeType: .native,
            healthcheck: plannedUnit.resolvedHealthcheck,
            port: plannedUnit.port?.number,
            dependsOn: plannedUnit.dependsOn
        )
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
