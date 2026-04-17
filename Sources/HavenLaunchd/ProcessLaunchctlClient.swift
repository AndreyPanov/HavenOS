import Foundation

/// Production implementation of `LaunchctlClient` using Foundation.Process.
///
/// Executes real `launchctl` commands against the current user's GUI domain.
/// All commands target `gui/<uid>` to operate within the user session.
public struct ProcessLaunchctlClient: LaunchctlClient, Sendable {

    /// The path to the launchctl binary.
    private static let launchctlPath = "/bin/launchctl"

    /// The current user's UID, used to construct the GUI domain target.
    private let uid: uid_t

    public init() {
        self.uid = getuid()
    }

    /// The GUI domain target for launchctl subcommands.
    /// Format: `gui/<uid>`
    var domainTarget: String {
        "gui/\(uid)"
    }

    /// Service target for a specific label within the GUI domain.
    /// Format: `gui/<uid>/<label>`
    func serviceTarget(label: String) -> String {
        "\(domainTarget)/\(label)"
    }

    // MARK: - LaunchctlClient

    public func bootstrap(plistPath: String) throws -> LaunchctlResult {
        try run(arguments: ["bootstrap", domainTarget, plistPath])
    }

    public func bootout(label: String) throws -> LaunchctlResult {
        try run(arguments: ["bootout", serviceTarget(label: label)])
    }

    public func start(label: String) throws -> LaunchctlResult {
        // Bootstrap re-loads the plist from disk and starts via RunAtLoad.
        // This avoids launchd's 10-second throttle that applies to kickstart
        // after a recent process exit.
        let plistPath = LaunchdPaths().plistPath(for: label).path
        return try run(arguments: ["bootstrap", "gui/\(uid)", plistPath])
    }

    public func stop(label: String) throws -> LaunchctlResult {
        // Bootout fully unloads the job (stops process + removes from launchd).
        // The plist remains on disk for re-bootstrap on next start.
        // This is cleaner than kill SIGTERM which keeps the job loaded
        // and subject to launchd's throttle on restart.
        try run(arguments: ["bootout", serviceTarget(label: label)])
    }

    public func print(label: String) throws -> LaunchctlResult {
        try run(arguments: ["print", serviceTarget(label: label)])
    }

    // MARK: - Process execution

    /// Run a launchctl command and capture its output.
    private func run(arguments: [String]) throws -> LaunchctlResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.launchctlPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return LaunchctlResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
