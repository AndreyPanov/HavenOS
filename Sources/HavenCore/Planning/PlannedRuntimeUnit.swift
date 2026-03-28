import Foundation

/// A fully resolved runtime unit ready for execution.
///
/// All placeholders have been expanded, ports assigned,
/// and dependencies resolved.
public struct PlannedRuntimeUnit: Equatable, Sendable {
    /// The original spec this was derived from.
    public let spec: RuntimeUnit

    /// Expanded launch arguments (placeholders resolved).
    public let resolvedLaunchArguments: [String]

    /// Expanded environment variables (placeholders resolved).
    public let resolvedEnvironment: [String: String]

    /// Assigned port, if any.
    public let port: PlannedPort?

    /// Expanded healthcheck (placeholders resolved in target), if any.
    public let resolvedHealthcheck: Healthcheck?

    /// IDs of units this unit depends on (for launch ordering).
    public let dependsOn: [String]

    /// The template context used for this unit's expansion.
    public let templateContext: TemplateContext

    public init(
        spec: RuntimeUnit,
        resolvedLaunchArguments: [String],
        resolvedEnvironment: [String: String],
        port: PlannedPort?,
        resolvedHealthcheck: Healthcheck?,
        dependsOn: [String],
        templateContext: TemplateContext
    ) {
        self.spec = spec
        self.resolvedLaunchArguments = resolvedLaunchArguments
        self.resolvedEnvironment = resolvedEnvironment
        self.port = port
        self.resolvedHealthcheck = resolvedHealthcheck
        self.dependsOn = dependsOn
        self.templateContext = templateContext
    }
}
