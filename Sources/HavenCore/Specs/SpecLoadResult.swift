import Foundation

/// The outcome of loading specs from disk.
///
/// On success the ``registry`` is populated. ``issues`` may still
/// contain non-fatal warnings even when loading succeeds.
/// On failure ``registry`` is `nil` and ``issues`` contains the errors.
public struct SpecLoadResult: Sendable {

    /// The validated, cross-referenced registry (nil when errors are present).
    public let registry: SpecRegistry?

    /// All issues found during loading (both errors and warnings).
    public let issues: [SpecLoadIssue]

    /// `true` when loading succeeded without errors. Warnings are allowed.
    public var succeeded: Bool { registry != nil && !issues.contains { $0.isError } }

    /// Only the warning-level issues.
    public var warnings: [SpecLoadIssue] { issues.filter { !$0.isError } }

    public init(registry: SpecRegistry?, issues: [SpecLoadIssue]) {
        self.registry = registry
        self.issues = issues
    }
}
