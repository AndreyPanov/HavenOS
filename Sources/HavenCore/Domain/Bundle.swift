import Foundation

/// A named collection of capabilities that form a deployable unit.
///
/// A bundle is the implementation of one or more capabilities.
/// Everything in a bundle is resolved, scheduled, and torn down
/// as a group.
///
/// Example: `"navidrome-single"` is a bundle that implements
/// the `"music"` capability using a single Navidrome instance.
public struct Bundle: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier, e.g. `"haven.bundle.navidrome-single"`.
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
    /// Example: a single-instance Navidrome bundle implementing the music capability.
    public static let navidromeSingleExample = Bundle(
        id: "haven.bundle.navidrome-single",
        name: "Navidrome (Single)",
        capabilityIDs: ["haven.capability.music"],
        runtimeUnitIDs: ["haven.unit.navidrome"],
        settings: [
            SettingField(
                key: "music_path",
                label: "Music library path",
                fieldType: .path,
                defaultValue: "/srv/music",
                required: true
            ),
            SettingField(
                key: "port",
                label: "HTTP port",
                fieldType: .integer,
                defaultValue: "4533"
            ),
        ]
    )
}
