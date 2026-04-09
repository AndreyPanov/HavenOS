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
    public let capability: String

    /// IDs of the runtime units that belong to this bundle.
    public let runtimeUnits: [String]

    /// User-configurable settings exposed by this bundle.
    public let settings: [SettingField]

    /// Optional version string for the bundle.
    public let version: String?

    /// Post-install setup instructions shown to the user after installation.
    public let instructions: String?

    public init(
        id: String,
        name: String,
        capability: String,
        runtimeUnits: [String] = [],
        settings: [SettingField] = [],
        version: String? = nil,
        instructions: String? = nil
    ) {
        self.id = id
        self.name = name
        self.capability = capability
        self.runtimeUnits = runtimeUnits
        self.settings = settings
        self.version = version
        self.instructions = instructions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        capability = try c.decode(String.self, forKey: .capability)
        runtimeUnits = try c.decodeIfPresent([String].self, forKey: .runtimeUnits) ?? []
        settings = try c.decodeIfPresent([SettingField].self, forKey: .settings) ?? []
        version = try c.decodeIfPresent(String.self, forKey: .version)
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions)
    }

    /// Validates that the bundle is well-formed.
    ///
    /// - id and name must be non-empty.
    /// - capability must be non-empty.
    /// - All setting fields must individually validate.
    public func validate() throws {
        if id.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Bundle id must not be empty.")
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Bundle name must not be empty.")
        }
        if capability.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Bundle capability must not be empty.")
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
        capability: "haven.capability.test-library",
        runtimeUnits: [
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
