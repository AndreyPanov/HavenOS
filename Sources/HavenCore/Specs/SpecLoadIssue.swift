import Foundation

/// A single problem found during spec loading.
///
/// Issues are collected — not thrown — so the loader can report
/// every problem in one pass rather than stopping at the first.
public struct SpecLoadIssue: Equatable, Sendable, CustomStringConvertible {

    /// The category of the problem.
    public enum Kind: String, Equatable, Sendable {
        /// The JSON file could not be parsed at all.
        case malformedJSON
        /// The JSON contained a key that does not map to any model property.
        case unknownField
        /// Two files define the same spec ID.
        case duplicateID
        /// A cross-reference (e.g. bundle → capability) points at an ID that was not loaded.
        case missingReference
        /// The decoded model failed its own `validate()` check.
        case validationFailure
    }

    /// What went wrong.
    public let kind: Kind

    /// Which file (or ID) is affected.
    public let source: String

    /// Human-readable explanation.
    public let detail: String

    public init(kind: Kind, source: String, detail: String) {
        self.kind = kind
        self.source = source
        self.detail = detail
    }

    public var description: String {
        "[\(kind.rawValue)] \(source): \(detail)"
    }
}
