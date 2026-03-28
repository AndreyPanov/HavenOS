import Foundation
import HavenCore

/// Registry that resolves the correct `RuntimeAdapter` for a given runtime type.
///
/// The registry is the single entry point for runtime preparation.
/// Upper layers ask for an adapter by `RuntimeType` and get back a
/// protocol-typed value they can call `prepare()` on.
///
/// Adding a new runtime is a three-step process:
/// 1. Create a struct conforming to `RuntimeAdapter`.
/// 2. Register it in the registry's initializer (or via `register`).
/// 3. Done — the planner, installer, and execution layers need no changes.
public struct RuntimeAdapterRegistry: Sendable {

    private let adaptersByType: [RuntimeUnit.RuntimeType: any RuntimeAdapter]

    /// Creates a registry with the given adapters.
    ///
    /// If multiple adapters claim the same `runtimeType`, the last one wins.
    public init(adapters: [any RuntimeAdapter]) {
        var dict: [RuntimeUnit.RuntimeType: any RuntimeAdapter] = [:]
        for adapter in adapters {
            dict[adapter.runtimeType] = adapter
        }
        self.adaptersByType = dict
    }

    /// Creates the default registry with all built-in adapters.
    public static func makeDefault() -> RuntimeAdapterRegistry {
        RuntimeAdapterRegistry(adapters: [
            NativeRuntimeAdapter(),
            PythonRuntimeAdapter(),
        ])
    }

    /// Look up the adapter for a runtime type.
    ///
    /// - Returns: The matching adapter, or `nil` if none is registered.
    public func adapter(for runtimeType: RuntimeUnit.RuntimeType) -> (any RuntimeAdapter)? {
        adaptersByType[runtimeType]
    }

    /// Prepare a planned unit using the appropriate adapter.
    ///
    /// This is a convenience that resolves the adapter and calls `prepare()`.
    ///
    /// - Throws: `RuntimeAdapterError.unsupportedRuntimeType` if no adapter
    ///   is registered, or any error from the adapter's `prepare()`.
    public func prepare(
        unit: RuntimeUnit,
        plannedUnit: PlannedRuntimeUnit,
        serviceLayout: ServiceDirectoryLayout
    ) throws -> PreparedRuntime {
        guard let adapter = adapter(for: unit.runtimeType) else {
            throw RuntimeAdapterError.unsupportedRuntimeType(
                unitID: unit.id,
                runtimeType: unit.runtimeType.rawValue
            )
        }
        return try adapter.prepare(
            unit: unit,
            plannedUnit: plannedUnit,
            serviceLayout: serviceLayout
        )
    }

    /// The set of runtime types that have registered adapters.
    public var supportedRuntimeTypes: Set<RuntimeUnit.RuntimeType> {
        Set(adaptersByType.keys)
    }
}
