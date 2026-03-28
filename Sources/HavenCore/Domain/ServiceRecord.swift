import Foundation

/// A snapshot record that ties a capability, its bundle, and its runtime units together.
///
/// ServiceRecord is a read-only aggregate used for status reporting
/// and introspection. It does not own lifecycle — that is the
/// responsibility of the runtime adapter layer.
public struct ServiceRecord: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier for this record (typically matches the bundle ID).
    public let id: String

    /// The capability being served.
    public let capability: Capability

    /// The bundle that implements the capability.
    public let bundle: Bundle

    /// The runtime units that make up this service.
    public let units: [RuntimeUnit]

    public init(
        id: String,
        capability: Capability,
        bundle: Bundle,
        units: [RuntimeUnit]
    ) {
        self.id = id
        self.capability = capability
        self.bundle = bundle
        self.units = units
    }

    /// Validates the record and all of its children.
    public func validate() throws {
        if id.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("ServiceRecord id must not be empty.")
        }
        try capability.validate()
        try bundle.validate()
        for unit in units {
            try unit.validate()
        }
    }
}

// MARK: - Example

extension ServiceRecord {
    /// Example: a complete test library service record.
    public static let testLibraryExample = ServiceRecord(
        id: "haven.bundle.test-library-basic",
        capability: .testLibraryExample,
        bundle: .testLibraryBasicExample,
        units: [.testDBExample, .testWorkerExample, .testWebExample]
    )
}
