import Foundation

/// Errors raised when a domain model fails validation.
public struct ValidationError: Error, LocalizedError, Equatable, Sendable {
    /// Human-readable description of what failed.
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
