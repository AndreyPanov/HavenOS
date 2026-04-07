import Foundation

/// Result of running a Python-related command.
public struct PythonCommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Abstraction over running shell commands for Python environment setup.
///
/// Enables testing without a real Python installation by injecting a
/// mock implementation.
public protocol PythonCommandRunner: Sendable {
    /// Run a command and return the result.
    ///
    /// - Parameters:
    ///   - executable: Absolute path to the executable.
    ///   - arguments: Command-line arguments.
    ///   - environment: Environment variables (replaces inherited env).
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?
    ) throws -> PythonCommandResult
}

/// Production implementation that uses `Foundation.Process`.
public struct ProcessPythonCommandRunner: PythonCommandRunner {

    public init() {}

    public func run(
        executable: String,
        arguments: [String],
        environment: [String: String]?
    ) throws -> PythonCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let env = environment {
            process.environment = env
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return PythonCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
