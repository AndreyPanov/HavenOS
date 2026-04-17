import Foundation
import HavenCore
import HavenRuntimes

/// A launchd job definition that can be serialized to a property list.
///
/// `LaunchdJob` models the subset of launchd plist keys that Haven uses
/// to manage services. It is a pure value type — it does not touch the
/// filesystem, invoke `launchctl`, or start any processes.
///
/// ## Supported plist keys
///
/// | Key                         | Source |
/// |-----------------------------|--------|
/// | `Label`                     | `LaunchdLabel.label(capabilityID:unitID:)` |
/// | `ProgramArguments`          | `[PreparedRuntime.executableURL.path] + PreparedRuntime.arguments` |
/// | `EnvironmentVariables`      | `PreparedRuntime.environment` |
/// | `WorkingDirectory`          | `PreparedRuntime.workingDirectory` |
/// | `StandardOutPath`           | `<logs>/<unit-id>.stdout.log` |
/// | `StandardErrorPath`         | `<logs>/<unit-id>.stderr.log` |
/// | `RunAtLoad`                 | Always `true` (start immediately on load) |
/// | `KeepAlive`                 | Configurable via `LaunchdKeepAlivePolicy` |
///
/// ## Creating a job
///
/// Use `LaunchdJob.make(capabilityID:unitID:preparedRuntime:serviceLayout:)`
/// to build a job from a prepared runtime.
public struct LaunchdJob: Equatable, Sendable {

    /// The unique launchd label for this job.
    public let label: String

    /// The program and its arguments (argv).
    /// The first element is the executable path.
    public let programArguments: [String]

    /// Environment variables to set for the process.
    public let environmentVariables: [String: String]

    /// The working directory for the process.
    public let workingDirectory: String

    /// Path where stdout is redirected.
    public let standardOutPath: String

    /// Path where stderr is redirected.
    public let standardErrorPath: String

    /// Whether to start the job immediately when loaded.
    public let runAtLoad: Bool

    /// Restart policy for the job.
    public let keepAlive: LaunchdKeepAlivePolicy

    public init(
        label: String,
        programArguments: [String],
        environmentVariables: [String: String],
        workingDirectory: String,
        standardOutPath: String,
        standardErrorPath: String,
        runAtLoad: Bool,
        keepAlive: LaunchdKeepAlivePolicy
    ) {
        self.label = label
        self.programArguments = programArguments
        self.environmentVariables = environmentVariables
        self.workingDirectory = workingDirectory
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
    }

    // MARK: - Factory

    /// Build a launchd job from a prepared runtime and service layout.
    ///
    /// This is the primary entry point for creating `LaunchdJob` values.
    /// It uses deterministic conventions for labels and log paths.
    ///
    /// - Parameters:
    ///   - capabilityID: The capability this unit belongs to.
    ///   - unitID: The runtime unit identifier.
    ///   - preparedRuntime: A fully prepared runtime from the adapter layer.
    ///   - serviceLayout: The service's directory layout (for log paths).
    ///   - keepAlive: Restart policy. Defaults to `.successfulExit`.
    /// - Returns: A `LaunchdJob` ready for plist serialization.
    public static func make(
        capabilityID: String,
        unitID: String,
        preparedRuntime: PreparedRuntime,
        serviceLayout: ServiceDirectoryLayout,
        keepAlive: LaunchdKeepAlivePolicy = .successfulExit
    ) -> LaunchdJob {
        let label = LaunchdLabel.label(capabilityID: capabilityID, unitID: unitID)
        let stdoutPath = logPath(unitID: unitID, stream: "stdout", serviceLayout: serviceLayout)
        let stderrPath = logPath(unitID: unitID, stream: "stderr", serviceLayout: serviceLayout)

        return LaunchdJob(
            label: label,
            programArguments: [preparedRuntime.executableURL.path] + preparedRuntime.arguments,
            environmentVariables: preparedRuntime.environment,
            workingDirectory: preparedRuntime.workingDirectory.path,
            standardOutPath: stdoutPath,
            standardErrorPath: stderrPath,
            runAtLoad: true,
            keepAlive: keepAlive
        )
    }

    // MARK: - Plist encoding

    /// Encode this job as a property list dictionary suitable for launchd.
    ///
    /// The returned dictionary uses only plist-compatible types (String,
    /// Bool, Array, Dictionary) and can be serialized with
    /// `PropertyListSerialization`.
    public func plistDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
            "WorkingDirectory": workingDirectory,
            "StandardOutPath": standardOutPath,
            "StandardErrorPath": standardErrorPath,
            "RunAtLoad": runAtLoad,
        ]

        if !environmentVariables.isEmpty {
            dict["EnvironmentVariables"] = environmentVariables
        }

        if keepAlive.shouldIncludeInPlist {
            dict["KeepAlive"] = keepAlive.plistValue()
        }

        // Disable launchd's default 10-second throttle between restarts.
        // Without this, rapid stop→start cycles are delayed.
        dict["ThrottleInterval"] = 1

        return dict
    }

    /// Serialize this job to XML property list data.
    ///
    /// - Throws: If `PropertyListSerialization` fails (should not happen
    ///   with well-formed input).
    /// - Returns: UTF-8 XML plist data ready to be written to disk.
    public func plistData() throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: plistDictionary(),
            format: .xml,
            options: 0
        )
    }

    // MARK: - Path helpers

    /// Compute the log file path for a given unit and stream.
    ///
    /// Layout: `<logs>/<unit-id>.<stream>.log`
    static func logPath(
        unitID: String,
        stream: String,
        serviceLayout: ServiceDirectoryLayout
    ) -> String {
        serviceLayout.logs
            .appendingPathComponent("\(unitID).\(stream).log")
            .path
    }
}
