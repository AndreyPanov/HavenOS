import Foundation

/// The type of guidance an onboarding step provides.
public enum OnboardingStepType: String, Codable, Equatable, Hashable, Sendable {
    /// Informational text — "here's what you need to know."
    case info
    /// Credentials to display — username, password, etc.
    case credentials
    /// An action the user should take — open a URL, configure a setting, etc.
    case action
}

/// A labeled key-value pair shown in an onboarding step (e.g., "Username": "admin").
///
/// Using a struct array instead of `[String: String]` preserves display order.
public struct OnboardingField: Codable, Equatable, Hashable, Sendable {
    /// Display label (e.g., "Username").
    public let label: String

    /// The value, which may contain `${variable}` placeholders before resolution.
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// A single structured onboarding step shown after installation.
public struct OnboardingStep: Codable, Equatable, Hashable, Sendable {
    /// The step type determines how the UI renders this step.
    public let type: OnboardingStepType

    /// Step title shown as a heading.
    public let title: String

    /// The body text. May contain `${variable}` placeholders before resolution.
    public let body: String

    /// Optional key-value fields (e.g., credentials). Order is preserved.
    public let fields: [OnboardingField]

    /// Optional URL for `action`-type steps. May contain `${variable}` placeholders.
    public let url: String?

    public init(
        type: OnboardingStepType,
        title: String,
        body: String,
        fields: [OnboardingField] = [],
        url: String? = nil
    ) {
        self.type = type
        self.title = title
        self.body = body
        self.fields = fields
        self.url = url
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(OnboardingStepType.self, forKey: .type)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decode(String.self, forKey: .body)
        fields = try c.decodeIfPresent([OnboardingField].self, forKey: .fields) ?? []
        url = try c.decodeIfPresent(String.self, forKey: .url)
    }

    /// Validates that the step is well-formed.
    public func validate() throws {
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Onboarding step title must not be empty.")
        }
        if body.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("Onboarding step body must not be empty.")
        }
    }
}

/// Container for a bundle's onboarding flow.
public struct Onboarding: Codable, Equatable, Hashable, Sendable {
    /// Ordered list of onboarding steps.
    public let steps: [OnboardingStep]

    public init(steps: [OnboardingStep]) {
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps = try c.decodeIfPresent([OnboardingStep].self, forKey: .steps) ?? []
    }

    /// Validates all steps.
    public func validate() throws {
        for step in steps {
            try step.validate()
        }
    }
}
