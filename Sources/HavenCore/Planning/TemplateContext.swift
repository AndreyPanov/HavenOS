import Foundation

/// A key-value bag used to expand `${placeholder}` references
/// in environment variables, launch arguments, and healthcheck targets.
///
/// The context is built per-runtime-unit from:
/// - resolved user settings
/// - derived directory paths
/// - port assignments
public struct TemplateContext: Equatable, Sendable {
    /// The raw key→value pairs available for expansion.
    public let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    /// Expand all `${key}` placeholders in `input` using this context's values.
    ///
    /// Unknown placeholders are left as-is so downstream layers
    /// can detect or report them.
    public func expand(_ input: String) -> String {
        var result = input
        for (key, value) in values {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
        }
        return result
    }

    /// Expand all values in a dictionary.
    public func expandValues(in dict: [String: String]) -> [String: String] {
        dict.mapValues { expand($0) }
    }

    /// Expand all elements in an array.
    public func expandAll(_ items: [String]) -> [String] {
        items.map { expand($0) }
    }
}
