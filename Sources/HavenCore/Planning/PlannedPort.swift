import Foundation

/// A port assignment for a planned runtime unit.
public struct PlannedPort: Equatable, Sendable {
    /// The port number.
    public let number: Int

    /// Where the value came from.
    public enum Source: String, Equatable, Sendable {
        /// Declared in the runtime unit spec.
        case spec
        /// Overridden by a user setting.
        case settingOverride
    }

    /// How this port number was determined.
    public let source: Source

    public init(number: Int, source: Source) {
        self.number = number
        self.source = source
    }
}
