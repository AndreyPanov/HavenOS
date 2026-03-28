import Foundation

/// The result of executing a launchctl command.
public struct LaunchctlResult: Equatable, Sendable {
    /// The process exit code. 0 indicates success.
    public let exitCode: Int32

    /// Captured standard output.
    public let stdout: String

    /// Captured standard error.
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    /// Whether the command exited successfully.
    public var succeeded: Bool { exitCode == 0 }
}

/// Abstraction over launchctl command execution.
///
/// The protocol enables testing without invoking real launchctl commands.
/// `ProcessLaunchctlClient` is the production implementation;
/// tests can provide a mock that records calls and returns canned results.
public protocol LaunchctlClient: Sendable {

    /// Bootstrap (load) a plist into the user domain.
    ///
    /// Equivalent to: `launchctl bootstrap gui/<uid> <plistPath>`
    func bootstrap(plistPath: String) throws -> LaunchctlResult

    /// Bootout (unload) a job from the user domain.
    ///
    /// Equivalent to: `launchctl bootout gui/<uid>/<label>`
    func bootout(label: String) throws -> LaunchctlResult

    /// Start a loaded job by label.
    ///
    /// Equivalent to: `launchctl kickstart gui/<uid>/<label>`
    func start(label: String) throws -> LaunchctlResult

    /// Stop a running job by label.
    ///
    /// Equivalent to: `launchctl kill SIGTERM gui/<uid>/<label>`
    func stop(label: String) throws -> LaunchctlResult

    /// Query the status of a job by label.
    ///
    /// Equivalent to: `launchctl print gui/<uid>/<label>`
    ///
    /// Returns the raw output for the controller to parse into
    /// `LaunchdJobStatus`.
    func print(label: String) throws -> LaunchctlResult
}
