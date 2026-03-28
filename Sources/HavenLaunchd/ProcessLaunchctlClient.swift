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
        try run(arguments: ["kickstart", serviceTarget(label: label)])
    }

    public func stop(label: String) throws -> LaunchctlResult {
        try run(arguments: ["kill", "SIGTERM", serviceTarget(label: label)])
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
