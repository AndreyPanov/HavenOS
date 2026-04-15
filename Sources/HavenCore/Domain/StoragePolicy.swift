import Foundation

/// Describes how a directory role's data should be treated by Haven.
///
/// Storage policies are declared at the bundle level and map to
/// directory roles defined in the runtime unit's `directories` block.
public struct StoragePolicy: Codable, Equatable, Sendable {

    /// If `true`, data in this directory survives uninstall and reinstall.
    /// Haven skips cleanup for persistent directories during uninstall.
    public let persistent: Bool

    /// If `true`, this directory is shown in the UI as a user-managed folder
    /// (e.g. "Your music library is at ~/Music").
    public let userVisible: Bool

    public init(persistent: Bool = true, userVisible: Bool = false) {
        self.persistent = persistent
        self.userVisible = userVisible
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        persistent = try c.decodeIfPresent(Bool.self, forKey: .persistent) ?? true
        userVisible = try c.decodeIfPresent(Bool.self, forKey: .userVisible) ?? false
    }
}
