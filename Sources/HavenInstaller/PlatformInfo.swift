import Foundation

/// Detects the current platform's operating system and CPU architecture.
///
/// Used by ``ArtifactResolver`` to select the correct platform-specific
/// asset from an artifact's asset list.
public struct PlatformInfo: Equatable, Sendable {

    /// The operating system identifier (e.g. `"macos"`).
    public let os: String

    /// The CPU architecture identifier (e.g. `"arm64"`, `"x86_64"`).
    public let arch: String

    public init(os: String, arch: String) {
        self.os = os
        self.arch = arch
    }

    /// The platform info for the machine running this process.
    public static var current: PlatformInfo {
        #if arch(arm64)
        PlatformInfo(os: "macos", arch: "arm64")
        #elseif arch(x86_64)
        PlatformInfo(os: "macos", arch: "x86_64")
        #else
        PlatformInfo(os: "macos", arch: "unknown")
        #endif
    }
}
