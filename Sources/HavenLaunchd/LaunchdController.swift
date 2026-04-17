import Foundation
import os

private let log = Logger(subsystem: "com.haven", category: "LaunchdController")

/// Manages the lifecycle of launchd jobs for Haven services.
///
/// `LaunchdController` is the primary API for installing, starting, stopping,
/// and uninstalling launchd jobs. It consumes `LaunchdJob` values (from the
/// modeling layer) and translates them into filesystem writes and launchctl
/// commands.
///
/// ## Architecture
///
/// ```
/// LaunchdJob (model) → LaunchdController → filesystem + launchctl
/// ```
///
/// The controller uses two dependencies:
/// - `LaunchdPaths` for deterministic file path resolution
/// - `LaunchctlClient` for executing launchctl commands (mockable for tests)
///
/// Upper layers should not need to know about launchctl, plist files, or
/// the GUI domain target. This controller encapsulates all of that.
public struct LaunchdController: Sendable {

    private let paths: LaunchdPaths
    private let client: any LaunchctlClient
    private nonisolated(unsafe) let fileManager: FileManager

    /// Creates a controller with the given dependencies.
    ///
    /// - Parameters:
    ///   - paths: Path resolver for LaunchAgents. Defaults to the standard
    ///     user LaunchAgents directory.
    ///   - client: The launchctl client for executing commands. Defaults
    ///     to `ProcessLaunchctlClient` for production use.
    public init(
        paths: LaunchdPaths = LaunchdPaths(),
        client: any LaunchctlClient = ProcessLaunchctlClient(),
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.client = client
        self.fileManager = fileManager
    }

    // MARK: - Install

    /// Install a launchd job: write its plist and load it into launchd.
    ///
    /// 1. Serializes the job to XML plist data.
    /// 2. Writes the plist file to the LaunchAgents directory (atomic write).
    /// 3. Bootstraps (loads) the job into the user's GUI domain.
    ///
    /// If the job has `runAtLoad = true`, launchd will start it immediately
    /// after bootstrap.
    ///
    /// - Parameter job: The launchd job definition to install.
    /// - Throws: `LaunchdControllerError` if any step fails.
    public func install(job: LaunchdJob) throws {
        log.info("[install] Installing job: \(job.label)")

        // 1. Serialize to plist data
        let data: Data
        do {
            data = try job.plistData()
            log.debug("[install] Plist serialized (\(data.count) bytes)")
        } catch {
            throw LaunchdControllerError.plistSerializationFailed(
                label: job.label,
                detail: error.localizedDescription
            )
        }

        // 2. Write plist file atomically
        let plistURL = paths.plistPath(for: job.label)
        log.info("[install] Writing plist: \(plistURL.path)")
        do {
            try writePlistAtomically(data: data, to: plistURL)
        } catch let error as LaunchdControllerError {
            throw error
        } catch {
            throw LaunchdControllerError.plistWriteFailed(
                label: job.label,
                path: plistURL.path,
                detail: error.localizedDescription
            )
        }

        // 3. Bootstrap into the user domain
        log.info("[install] Bootstrapping job into user domain...")
        let result: LaunchctlResult
        do {
            result = try client.bootstrap(plistPath: plistURL.path)
        } catch {
            throw LaunchdControllerError.loadFailed(
                label: job.label,
                detail: error.localizedDescription
            )
        }

        guard result.succeeded else {
            log.error("[install] Bootstrap failed: \(combinedOutput(result))")
            throw LaunchdControllerError.loadFailed(
                label: job.label,
                detail: combinedOutput(result)
            )
        }
        log.info("[install] Job installed: \(job.label)")
    }

    // MARK: - Uninstall

    /// Uninstall a launchd job: unload it from launchd and remove its plist.
    ///
    /// 1. Bootout (unload) the job from the user's GUI domain.
    /// 2. Remove the plist file from the LaunchAgents directory.
    ///
    /// If the job is currently running, bootout will stop it first.
    ///
    /// - Parameter label: The launchd job label to uninstall.
    /// - Throws: `LaunchdControllerError` if any step fails.
    public func uninstall(label: String) throws {
        log.info("[uninstall] Booting out job: \(label)")
        // 1. Bootout from the user domain
        let result: LaunchctlResult
        do {
            result = try client.bootout(label: label)
        } catch {
            throw LaunchdControllerError.unloadFailed(
                label: label,
                detail: error.localizedDescription
            )
        }

        if !result.succeeded {
            let output = combinedOutput(result)
            // "No such process" means the job is already gone — not an error.
            if output.contains("No such process") || output.contains("Could not find service") {
                log.info("[uninstall] Job already unloaded: \(label)")
            } else {
                log.error("[uninstall] Bootout failed: \(output)")
                throw LaunchdControllerError.unloadFailed(
                    label: label,
                    detail: output
                )
            }
        }

        // 2. Remove the plist file
        let plistURL = paths.plistPath(for: label)
        log.info("[uninstall] Removing plist: \(plistURL.path)")
        do {
            try fileManager.removeItem(at: plistURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileNoSuchFileError
        {
            log.info("[uninstall] Plist already removed")
        } catch {
            throw LaunchdControllerError.plistRemoveFailed(
                label: label,
                path: plistURL.path,
                detail: error.localizedDescription
            )
        }
        log.info("[uninstall] Job uninstalled: \(label)")
    }

    // MARK: - Start

    /// Start a service by bootstrapping its plist into launchd.
    ///
    /// Uses `bootstrap` to load the plist from disk, which also starts the
    /// job via `RunAtLoad`. If the job is already loaded (e.g. first start
    /// after install), bootstrap returns "already loaded" — this is not an error.
    ///
    /// - Parameter label: The launchd job label to start.
    /// - Throws: `LaunchdControllerError.startFailed` if the command fails.
    public func start(label: String) throws {
        log.info("[start] Starting job: \(label)")
        let result: LaunchctlResult
        do {
            result = try client.start(label: label)
        } catch {
            throw LaunchdControllerError.startFailed(
                label: label,
                detail: error.localizedDescription
            )
        }

        if !result.succeeded {
            let output = combinedOutput(result)
            log.info("[start] Bootstrap failed (\(output)), clearing stale state and retrying")
            // Bootstrap can fail with error 5 (stale launchd state) or
            // "already loaded". Clear stale state with bootout, then retry.
            let _ = try? client.bootout(label: label)
            let retryResult = try client.start(label: label)
            if !retryResult.succeeded {
                let retryOutput = combinedOutput(retryResult)
                log.error("[start] Retry bootstrap also failed: \(retryOutput)")
                throw LaunchdControllerError.startFailed(
                    label: label,
                    detail: "bootstrap: \(output); retry: \(retryOutput)"
                )
            }
        }
        log.info("[start] Job started: \(label)")
    }

    /// Kickstart a loaded job (fallback when bootstrap reports already loaded).
    private func kickstart(label: String) throws -> LaunchctlResult {
        let serviceTarget = "gui/\(getuid())/\(label)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", serviceTarget]

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

    // MARK: - Stop

    /// Stop a running job.
    ///
    /// Sends SIGTERM to the job's process. The job remains loaded in launchd
    /// and may be restarted depending on its keep-alive policy.
    ///
    /// - Parameter label: The launchd job label to stop.
    /// - Throws: `LaunchdControllerError.stopFailed` if the command fails.
    public func stop(label: String) throws {
        log.info("[stop] Stopping job: \(label)")
        let result: LaunchctlResult
        do {
            result = try client.stop(label: label)
        } catch {
            throw LaunchdControllerError.stopFailed(
                label: label,
                detail: error.localizedDescription
            )
        }

        if !result.succeeded {
            let output = combinedOutput(result)
            // These mean the job is already stopped/unloaded — not an error.
            if output.contains("No process to signal") || output.contains("No such process")
                || output.contains("Could not find service") {
                log.info("[stop] Job already stopped: \(label)")
            } else {
                log.error("[stop] Stop failed: \(output)")
                throw LaunchdControllerError.stopFailed(
                    label: label,
                    detail: output
                )
            }
        } else {
            log.info("[stop] Job stopped: \(label)")
        }
    }

    // MARK: - Status

    /// Query the current status of a launchd job.
    ///
    /// Examines both the filesystem (plist exists?) and launchd state
    /// (loaded? running? PID? exit status?) to build a complete picture.
    ///
    /// - Parameter label: The launchd job label to query.
    /// - Returns: The observed status of the job.
    /// - Throws: `LaunchdControllerError.statusQueryFailed` if the query fails
    ///   in an unexpected way.
    public func status(label: String) throws -> LaunchdJobStatus {
        log.debug("[status] Querying job: \(label)")
        let plistURL = paths.plistPath(for: label)
        let plistExists = fileManager.fileExists(atPath: plistURL.path)

        let result: LaunchctlResult
        do {
            result = try client.print(label: label)
        } catch {
            throw LaunchdControllerError.statusQueryFailed(
                label: label,
                detail: error.localizedDescription
            )
        }

        // If launchctl print fails, the job is either not loaded or not found
        if !result.succeeded {
            if plistExists {
                return LaunchdJobStatus(state: .installed, label: label)
            } else {
                return LaunchdJobStatus(state: .notFound, label: label)
            }
        }

        // Parse the output to determine running state
        return Self.parseStatus(label: label, output: result.stdout)
    }

    // MARK: - Status parsing

    /// Parse `launchctl print` output into a `LaunchdJobStatus`.
    ///
    /// The output contains lines like:
    /// ```
    /// pid = 12345
    /// last exit code = 0
    /// state = running
    /// ```
    ///
    /// This parser looks for known patterns to extract PID, exit status,
    /// and run state.
    static func parseStatus(label: String, output: String) -> LaunchdJobStatus {
        var pid: Int?
        var lastExitStatus: Int?
        var state: LaunchdJobStatus.State = .stopped

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("pid = ") {
                let value = trimmed.dropFirst("pid = ".count)
                if let parsed = Int(value) {
                    pid = parsed
                }
            } else if trimmed.hasPrefix("last exit code = ") {
                let value = trimmed.dropFirst("last exit code = ".count)
                if let parsed = Int(value) {
                    lastExitStatus = parsed
                }
            } else if trimmed.hasPrefix("state = ") {
                let value = String(trimmed.dropFirst("state = ".count))
                if value == "running" {
                    state = .running
                } else {
                    state = .stopped
                }
            }
        }

        // If we have a PID, the job is running regardless of state line
        if pid != nil {
            state = .running
        }

        return LaunchdJobStatus(
            state: state,
            pid: pid,
            lastExitStatus: lastExitStatus,
            label: label
        )
    }

    // MARK: - Private helpers

    /// Write plist data to a file atomically, creating parent directories.
    private func writePlistAtomically(data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        // Write to a temp file and rename for atomicity
        let tempName = ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        let tempURL = directory.appendingPathComponent(tempName)

        do {
            try data.write(to: tempURL, options: .atomic)
            _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw LaunchdControllerError.plistWriteFailed(
                label: url.deletingPathExtension().lastPathComponent,
                path: url.path,
                detail: error.localizedDescription
            )
        }
    }

    /// Combine stdout and stderr for error detail messages.
    private func combinedOutput(_ result: LaunchctlResult) -> String {
        var parts: [String] = []
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty { parts.append(stdout) }
        if !stderr.isEmpty { parts.append(stderr) }
        if parts.isEmpty { return "exit code \(result.exitCode)" }
        return parts.joined(separator: "; ")
    }
}
