import Foundation

/// A named collection of capabilities that form a deployable unit.
///
/// A bundle is the implementation of one or more capabilities.
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

    /// IDs of the capabilities this bundle implements.
    public let capabilityIDs: [String]

    /// IDs of the runtime units that belong to this bundle.
    public let runtimeUnitIDs: [String]

    /// User-configurable settings exposed by this bundle.
    public let settings: [SettingField]

    public init(
        id: String,
        name: String,
        capabilityIDs: [String],
        runtimeUnitIDs: [String] = [],
        settings: [SettingField] = []
    ) {
        self.id = id
        self.name = name
        self.capabilityIDs = capabilityIDs
        self.runtimeUnitIDs = runtimeUnitIDs
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        capabilityIDs = try c.decode([String].self, forKey: .capabilityIDs)
        runtimeUnitIDs = try c.decodeIfPresent([String].self, forKey: .runtimeUnitIDs) ?? []
        settings = try c.decodeIfPresent([SettingField].self, forKey: .settings) ?? []
    }

    /// Validates that the bundle is well-formed.
    ///
    /// - id and name must be non-empty.
    /// - Must reference at least one capability ID.
    /// - All setting fields must individually validate.
    public func validate() throws {
        if id.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Bundle id must not be empty.")
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Bundle name must not be empty.")
        }
        if capabilityIDs.isEmpty {
            throw ValidationError("Bundle must reference at least one capability ID.")
        }
        for capID in capabilityIDs where capID.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Bundle capability ID must not be empty.")
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
        capabilityIDs: ["haven.capability.test-library"],
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
