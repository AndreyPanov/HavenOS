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

    // MARK: - Onboarding expansion

    /// Expand all placeholders in an ``OnboardingField``.
    public func expand(_ field: OnboardingField) -> OnboardingField {
        OnboardingField(label: field.label, value: expand(field.value))
    }

    /// Expand all placeholders in an ``OnboardingStep``.
    public func expand(_ step: OnboardingStep) -> OnboardingStep {
        OnboardingStep(
            type: step.type,
            title: expand(step.title),
            body: expand(step.body),
            fields: step.fields.map { expand($0) },
            url: step.url.map { expand($0) }
        )
    }

    /// Expand all placeholders in an ``Onboarding``.
    public func expand(_ onboarding: Onboarding) -> Onboarding {
        Onboarding(steps: onboarding.steps.map { expand($0) })
    }

    // MARK: - Provision expansion

    /// Expand all placeholders in a ``Provision``.
    public func expand(_ provision: Provision) -> Provision {
        Provision(
            description: provision.description,
            source: expand(provision.source),
            destination: expand(provision.destination),
            condition: provision.condition
        )
    }

    // MARK: - Readiness probe expansion

    /// Expand all placeholders in a ``ReadinessProbe``.
    public func expand(_ probe: ReadinessProbe) -> ReadinessProbe {
        ReadinessProbe(
            type: probe.type,
            target: expand(probe.target),
            timeoutSeconds: probe.timeoutSeconds,
            intervalSeconds: probe.intervalSeconds
        )
    }

    // MARK: - Install step expansion

    /// Expand all placeholders in an ``InstallStep``.
    public func expand(_ step: InstallStep) -> InstallStep {
        InstallStep(
            action: step.action,
            path: expand(step.path),
            source: step.source.map { expand($0) },
            mode: step.mode,
            content: step.content.map { expand($0) },
            arguments: step.arguments.map { expandAll($0) },
            ifNotExists: step.ifNotExists
        )
    }

    /// Expand all placeholders in an ``InstallBlock``.
    public func expand(_ block: InstallBlock) -> InstallBlock {
        InstallBlock(steps: block.steps.map { expand($0) })
    }
}
