import Foundation
import HavenCore
import os

private let log = Logger(subsystem: "com.haven", category: "DependencyValidator")

/// Validates that external dependencies declared by runtime units are
/// present on the system.
///
/// Uses deterministic absolute paths for discovery — never relies on
/// the user's `$PATH`. For `helperBinary` dependencies, probes
/// well-known directories in order. If a `validateCommand` is provided,
/// runs it as extra verification.
///
/// ## Design Principles
///
/// - **Deterministic**: search paths are hardcoded, not inherited from env
/// - **No tooling exposure**: user-facing errors never mention brew, apt, etc.
/// - **Fail fast**: required deps block install; optional deps warn only
public struct DependencyValidator: Sendable {

    /// Well-known directories to search for helper binaries, in priority order.
    static let searchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
    ]

    private nonisolated(unsafe) let fileManager: FileManager

    /// Closure that runs a shell command and returns whether it exited 0.
    /// Injectable for testing.
    let commandRunner: @Sendable (String) -> Bool

    public init(
        fileManager: FileManager = .default,
        commandRunner: @escaping @Sendable (String) -> Bool = DependencyValidator.runCommand
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
    }

    /// Validate a list of dependencies.
    ///
    /// - Parameter dependencies: The dependencies to check.
    /// - Returns: A result per dependency, in the same order.
    public func validate(dependencies: [Dependency]) -> [DependencyResult] {
        // Deduplicate by id (multiple units may declare the same dep)
        var seen = Set<String>()
        var unique: [Dependency] = []
        for dep in dependencies {
            if seen.insert(dep.id).inserted {
                unique.append(dep)
            }
        }

        return unique.map { dep in
            switch dep.kind {
            case .helperBinary:
                return validateHelperBinary(dep)
            case .library:
                return validateLibrary(dep)
            }
        }
    }

    // MARK: - Helper Binary

    private func validateHelperBinary(_ dep: Dependency) -> DependencyResult {
        // 1. Search well-known paths for the binary by id
        for dir in Self.searchPaths {
            let path = "\(dir)/\(dep.id)"
            if fileManager.isExecutableFile(atPath: path) {
                log.info("[dependency] Found '\(dep.id)' at \(path)")

                // 2. If validateCommand is provided, run it as extra check
                if let command = dep.validateCommand {
                    let fullCommand = resolveCommand(command, binaryPath: path)
                    if commandRunner(fullCommand) {
                        log.info("[dependency] Validate command passed for '\(dep.id)'")
                        return DependencyResult(dependency: dep, status: .found(path: path))
                    } else {
                        log.warning("[dependency] '\(dep.id)' found at \(path) but validate command failed")
                        // Binary exists but validate failed — treat as missing
                        continue
                    }
                }

                return DependencyResult(dependency: dep, status: .found(path: path))
            }
        }

        // 3. If validateCommand starts with an absolute path, try it directly
        if let command = dep.validateCommand, command.hasPrefix("/") {
            if commandRunner(command) {
                let binaryPath = String(command.split(separator: " ").first ?? "")
                log.info("[dependency] Validate command succeeded for '\(dep.id)' (direct path)")
                return DependencyResult(dependency: dep, status: .found(path: binaryPath))
            }
        }

        log.warning("[dependency] '\(dep.id)' not found (required=\(dep.required))")
        return DependencyResult(dependency: dep, status: .missing)
    }

    // MARK: - Library

    private func validateLibrary(_ dep: Dependency) -> DependencyResult {
        // Libraries can only be validated via validateCommand
        if let command = dep.validateCommand {
            if commandRunner(command) {
                log.info("[dependency] Library '\(dep.id)' validated via command")
                return DependencyResult(dependency: dep, status: .found(path: ""))
            }
        }

        log.warning("[dependency] Library '\(dep.id)' could not be validated (required=\(dep.required))")
        return DependencyResult(dependency: dep, status: .missing)
    }

    // MARK: - Helpers

    /// If the validate command uses a bare binary name, substitute the
    /// resolved absolute path.
    private func resolveCommand(_ command: String, binaryPath: String) -> String {
        if command.hasPrefix("/") {
            return command
        }
        // Replace bare binary name with absolute path
        // e.g. "ffmpeg -version" → "/opt/homebrew/bin/ffmpeg -version"
        let binaryName = URL(fileURLWithPath: binaryPath).lastPathComponent
        if command.hasPrefix(binaryName) {
            return binaryPath + command.dropFirst(binaryName.count)
        }
        return command
    }

    /// Default command runner using Process.
    public static let runCommand: @Sendable (String) -> Bool = { command in
        let parts = command.split(separator: " ", maxSplits: 1)
        guard let executable = parts.first else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: String(executable))
        if parts.count > 1 {
            process.arguments = String(parts[1]).split(separator: " ").map(String.init)
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

/// The result of validating a single dependency.
public struct DependencyResult: Sendable, Equatable {
    /// The dependency that was checked.
    public let dependency: Dependency

    /// Whether the dependency was found.
    public let status: Status

    public enum Status: Sendable, Equatable {
        /// Found at the given absolute path.
        case found(path: String)
        /// Not found on the system.
        case missing
    }

    /// Whether this is a required dependency that is missing.
    public var isBlocker: Bool {
        dependency.required && status == .missing
    }

    /// Whether this is an optional dependency that is missing.
    public var isWarning: Bool {
        !dependency.required && status == .missing
    }
}
