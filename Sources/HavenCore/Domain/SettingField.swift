import Foundation

/// A single user-configurable setting exposed by a bundle.
///
/// Setting fields describe the knobs a user can tweak when
/// deploying a bundle — ports, paths, feature flags, etc.
public struct SettingField: Codable, Equatable, Sendable {

    /// The kind of value a setting field holds.
    public enum FieldType: String, Codable, Equatable, Sendable {
        case string
        case integer
        case boolean
        case path
    }

    /// Machine-readable key. Must be a valid identifier
    /// (alphanumerics and underscores, not starting with a digit).
    public let key: String

    /// Human-readable label.
    public let label: String

    /// The data type of this field.
    public let fieldType: FieldType

    /// Default value expressed as a string (decoded by consumers).
    public let defaultValue: String?

    /// Whether the user must supply a value.
    public let required: Bool

    public init(
        key: String,
        label: String,
        fieldType: FieldType,
        defaultValue: String? = nil,
        required: Bool = false
    ) {
        self.key = key
        self.label = label
        self.fieldType = fieldType
        self.defaultValue = defaultValue
        self.required = required
    }

    // MARK: - Validation

    /// Validates that the key is a valid identifier and the label is non-empty.
    public func validate() throws {
        if key.isEmpty {
            throw ValidationError("SettingField key must not be empty.")
        }
        // A valid identifier starts with a letter or underscore and
        // contains only alphanumerics and underscores.
        let identifierPattern = "^[A-Za-z_][A-Za-z0-9_]*$"
        if key.range(of: identifierPattern, options: .regularExpression) == nil {
            throw ValidationError(
                "SettingField key '\(key)' is not a valid identifier."
            )
        }
        if label.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("SettingField label must not be empty.")
        }
    }
}
