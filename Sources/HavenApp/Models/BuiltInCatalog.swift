import HavenCore

/// Built-in service specs defined in Swift.
///
/// Each capability adds its spec via an extension on this enum
/// (e.g. `Capabilities/Books/KavitaSpec.swift`). The `entries` array
/// collects them all for registry and catalog construction.
enum BuiltInCatalog {

    /// All built-in specs, ready to merge into a SpecRegistry.
    static let entries: [(Capability, HavenCore.Bundle, [RuntimeUnit])] = [
        kavita,
    ]

    /// Build a SpecRegistry from built-in entries alone.
    static func makeRegistry() -> SpecRegistry {
        var caps: [String: Capability] = [:]
        var bundles: [String: HavenCore.Bundle] = [:]
        var units: [String: RuntimeUnit] = [:]

        for (cap, bundle, runtimeUnits) in entries {
            caps[cap.id] = cap
            bundles[bundle.id] = bundle
            for unit in runtimeUnits {
                units[unit.id] = unit
            }
        }

        return SpecRegistry(
            capabilitiesByID: caps,
            bundlesByID: bundles,
            runtimeUnitsByID: units
        )
    }

    /// Build catalog entries (for UI display) from built-in specs.
    static func makeCatalogEntries() -> [CatalogEntry] {
        entries.map { cap, bundle, _ in
            let meta = CatalogMetadata(
                icon: cap.icon ?? "shippingbox",
                iconImagePath: cap.iconImage,
                notes: cap.notes,
                fullDescription: cap.fullDescription ?? cap.description ?? ""
            )
            return CatalogEntry(capability: cap, bundle: bundle, metadata: meta)
        }
    }
}
