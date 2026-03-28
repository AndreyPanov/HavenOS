import Foundation
import HavenCore

/// Contract for runtime-specific preparation of service units.
///
/// A `RuntimeAdapter` knows how to turn a planned runtime unit into
/// a launch-ready `PreparedRuntime`. Each adapter encapsulates one
/// execution environment (native binary, Python, etc.).
///
/// Adapters are pure preparation logic — they do not start processes,
/// create files on disk, or perform network calls. They compute the
/// deterministic preparation result that an execution layer can apply.
///
/// ## Design intent
///
/// Upper layers never need to know _how_ a native binary differs from
/// a Python app. They call `prepare()`, get a `PreparedRuntime`, and
/// hand it to the execution layer.
public protocol RuntimeAdapter: Sendable {

    /// The runtime type this adapter handles.
    var runtimeType: RuntimeUnit.RuntimeType { get }

    /// Prepare a runtime unit for launch.
    ///
    /// - Parameters:
    ///   - unit: The original runtime unit spec.
    ///   - plannedUnit: The fully resolved planned unit (placeholders expanded).
    ///   - serviceLayout: The directory layout for the owning service.
    /// - Returns: A `PreparedRuntime` containing everything needed to launch.
    /// - Throws: `RuntimeAdapterError` if preparation fails.
    func prepare(
        unit: RuntimeUnit,
        plannedUnit: PlannedRuntimeUnit,
        serviceLayout: ServiceDirectoryLayout
    ) throws -> PreparedRuntime

    /// Clean up runtime-owned artifacts for an uninstalled unit.
    ///
    /// - Parameters:
    ///   - preparedRuntime: The previously prepared runtime to tear down.
    ///   - serviceLayout: The directory layout for the owning service.
    /// - Throws: `RuntimeAdapterError` if teardown fails.
    func teardown(
        preparedRuntime: PreparedRuntime,
        serviceLayout: ServiceDirectoryLayout
    ) throws
}
