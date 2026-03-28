import Foundation

/// An in-memory, read-only store of validated specs.
///
/// Built by ``SpecLoader`` after all JSON files have been decoded,
/// deduplicated, and cross-referenced. Look up any spec by its ID
/// in O(1).
public struct SpecRegistry: Sendable {

    /// All loaded capabilities keyed by ID.
    public let capabilitiesByID: [String: Capability]

    /// All loaded bundles keyed by ID.
    public let bundlesByID: [String: Bundle]

    /// All loaded runtime units keyed by ID.
    public let runtimeUnitsByID: [String: RuntimeUnit]

    public init(
        capabilitiesByID: [String: Capability],
        bundlesByID: [String: Bundle],
        runtimeUnitsByID: [String: RuntimeUnit]
    ) {
        self.capabilitiesByID = capabilitiesByID
        self.bundlesByID = bundlesByID
        self.runtimeUnitsByID = runtimeUnitsByID
    }
}
