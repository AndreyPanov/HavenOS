import Foundation

/// The outcome of loading specs from disk.
///
/// On success the ``registry`` is populated and ``issues`` is empty.
/// On failure ``registry`` is `nil` and ``issues`` contains every
/// problem the loader encountered.
public struct SpecLoadResult: Sendable {

    /// The validated, cross-referenced registry (nil when issues are present).
    public let registry: SpecRegistry?

    /// All issues found during loading. Empty on success.
    public let issues: [SpecLoadIssue]

    /// `true` when loading succeeded without issues.
    public var succeeded: Bool { registry != nil && issues.isEmpty }

    public init(registry: SpecRegistry?, issues: [SpecLoadIssue]) {
        self.registry = registry
        self.issues = issues
    }
}
