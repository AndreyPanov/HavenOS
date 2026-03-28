import Foundation

/// A named collection of runtime units that implements a single capability.
///
/// A bundle is the deployable implementation of exactly one capability.
/// Everything in a bundle is resolved, scheduled, and torn down
/// as a group.
///
/// Example: `"test-library-basic"` is a bundle that implements
/// the `"test-library"` capability using three runtime units.
public struct Bundle: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier, e.g. `"haven.bundle.test-library-basic"`.
    public let id: String

    /// Human-readable display name.
    public let name: String

    /// ID of the capability this bundle implements.
    public let capabilityID: String

    /// IDs of the runtime units that belong to this bundle.
    public let runtimeUnitIDs: [String]

    /// User-configurable settings exposed by this bundle.
    public let settings: [SettingField]

    public init(
        id: String,
        name: String,
        capabilityID: String,
        runtimeUnitIDs: [String] = [],
        settings: [SettingField] = []
    ) {
        self.id = id
        self.name = name
        self.capabilityID = capabilityID
        self.runtimeUnitIDs = runtimeUnitIDs
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        capabilityID = try c.decode(String.self, forKey: .capabilityID)
        runtimeUnitIDs = try c.decodeIfPresent([String].self, forKey: .runtimeUnitIDs) ?? []
        settings = try c.decodeIfPresent([SettingField].self, forKey: .settings) ?? []
    }

    /// Validates that the bundle is well-formed.
    ///
    /// - id and name must be non-empty.
    /// - capabilityID must be non-empty.
    /// - All setting fields must individually validate.
    public func validate() throws {
        if id.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Bundle id must not be empty.")
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Bundle name must not be empty.")
        }
        if capabilityID.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Bundle capabilityID must not be empty.")
        }
        for setting in settings {
            try setting.validate()
        }
    }
}

// MARK: - Example

extension Bundle {
    /// Example: a test library bundle with three runtime units.
    public static let testLibraryBasicExample = Bundle(
        id: "haven.bundle.test-library-basic",
        name: "Test Library (Basic)",
        capabilityID: "haven.capability.test-library",
        runtimeUnitIDs: [
            "haven.unit.test-db",
            "haven.unit.test-worker",
            "haven.unit.test-web",
        ],
        settings: [
            SettingField(
                key: "data_path",
                label: "Data directory path",
                fieldType: .path,
                defaultValue: "/srv/data",
                required: true
            ),
            SettingField(
                key: "port",
                label: "HTTP port",
                fieldType: .integer,
                defaultValue: "8080"
            ),
        ]
    )
}
