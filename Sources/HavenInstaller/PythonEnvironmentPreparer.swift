import Foundation
import HavenCore
import os

private let log = Logger(subsystem: "com.haven", category: "PythonPreparer")

/// Creates and manages Python virtual environments for Haven services.
///
/// `PythonEnvironmentPreparer` handles:
/// 1. Locating the system Python 3 interpreter
/// 2. Creating a per-unit virtual environment
/// 3. Installing the specified package via pip
/// 4. Validating the module entrypoint is importable
///
/// ## Directory layout
///
/// ```
/// <basePath>/Installed/python/<unit-id>/venv/
///   bin/python3       ← interpreter
///   bin/pip3          ← package manager
///   lib/              ← installed packages
/// ```
///
/// Environments are created atomically using a staging directory
/// (`<unit-id>.creating`) that is promoted to the final location only
/// after all steps succeed.
///
/// ## Temporary: System Python discovery
///
/// This preparer locates Python from well-known absolute paths.
/// Future versions will use a Haven-managed Python runtime.
public struct PythonEnvironmentPreparer: Sendable {

    /// Well-known Python 3 interpreter paths, in priority order.
    /// No $PATH resolution — absolute paths only.
    static let pythonSearchPaths: [String] = [
        "/usr/bin/python3",
        "/usr/local/bin/python3",
        "/opt/homebrew/bin/python3",
    ]

    private let commandRunner: any PythonCommandRunner
    private nonisolated(unsafe) let fileManager: FileManager

    public init(
        commandRunner: any PythonCommandRunner = ProcessPythonCommandRunner(),
        fileManager: FileManager = .default
    ) {
        self.commandRunner = commandRunner
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Prepare a Python virtual environment for the given unit.
    ///
    /// If a valid cached environment exists, it is reused. Otherwise a new
    /// environment is created atomically.
    ///
    /// - Parameters:
    ///   - pythonConfig: The Python configuration from the RuntimeUnit spec.
    ///   - unitID: The runtime unit identifier.
    ///   - basePath: The Haven base directory (e.g. `~/.haven`).
    /// - Returns: A `PythonEnvironmentResult` with paths and metadata.
    /// - Throws: `PythonEnvironmentError` if any step fails.
    public func prepare(
        pythonConfig: RuntimeUnit.PythonConfig,
        unitID: String,
        basePath: URL
    ) throws -> PythonEnvironmentResult {
        log.info("[prepare] Setting up Python env for \(unitID): \(pythonConfig.package)==\(pythonConfig.version)")

        // 1. Find system Python
        let systemPython = try findSystemPython()
        log.info("[prepare] Using system Python: \(systemPython)")

        // 2. Compute paths
        let unitRoot = pythonUnitRoot(unitID: unitID, basePath: basePath)
        let venvDir = unitRoot.appendingPathComponent("venv")
        let venvPython = venvDir
            .appendingPathComponent("bin")
            .appendingPathComponent("python3")

        // 3. Check if existing venv is valid → cache hit
        if isVenvValid(venvDirectory: venvDir, pythonConfig: pythonConfig) {
            log.info("[prepare] Existing venv is valid — cache hit")
            return PythonEnvironmentResult(
                unitID: unitID,
                venvDirectory: venvDir,
                pythonPath: venvPython,
                package: pythonConfig.package,
                version: pythonConfig.version,
                wasCached: true
            )
        }

        // 4. Existing venv is broken or absent — (re)install
        //    Remove broken venv if present (do NOT remove during staging)
        if fileManager.fileExists(atPath: venvDir.path) {
            log.info("[prepare] Removing broken venv at \(venvDir.path)")
            try? fileManager.removeItem(at: venvDir)
        }

        // 5. Create staging directory
        let stagingDir = unitRoot.appendingPathComponent("\(unitID).creating")
        if fileManager.fileExists(atPath: stagingDir.path) {
            try? fileManager.removeItem(at: stagingDir)
        }
        try fileManager.createDirectory(at: unitRoot, withIntermediateDirectories: true)

        log.info("[prepare] Creating venv at staging: \(stagingDir.path)")

        // 6. Create venv
        let venvResult = try commandRunner.run(
            executable: systemPython,
            arguments: ["-m", "venv", stagingDir.path],
            environment: nil
        )
        guard venvResult.exitCode == 0 else {
            try? fileManager.removeItem(at: stagingDir)
            throw PythonEnvironmentError.venvCreationFailed(
                unitID: unitID,
                detail: venvResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        // 7. Install package via pip
        let stagingPip = stagingDir
            .appendingPathComponent("bin")
            .appendingPathComponent("pip3")
        let packageSpec = "\(pythonConfig.package)==\(pythonConfig.version)"

        log.info("[prepare] Installing package: \(packageSpec)")
        let pipResult = try commandRunner.run(
            executable: stagingPip.path,
            arguments: ["install", packageSpec],
            environment: [
                "VIRTUAL_ENV": stagingDir.path,
                "PATH": "\(stagingDir.appendingPathComponent("bin").path):/usr/bin:/bin",
            ]
        )
        guard pipResult.exitCode == 0 else {
            try? fileManager.removeItem(at: stagingDir)
            throw PythonEnvironmentError.packageInstallFailed(
                unitID: unitID,
                package: packageSpec,
                detail: pipResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        // 8. Validate module import
        let stagingPython = stagingDir
            .appendingPathComponent("bin")
            .appendingPathComponent("python3")
        let module = pythonConfig.entrypoint.module

        log.info("[prepare] Validating module import: \(module)")
        let validateResult = try commandRunner.run(
            executable: stagingPython.path,
            arguments: ["-c", "import \(module)"],
            environment: [
                "VIRTUAL_ENV": stagingDir.path,
                "PATH": "\(stagingDir.appendingPathComponent("bin").path):/usr/bin:/bin",
            ]
        )
        guard validateResult.exitCode == 0 else {
            try? fileManager.removeItem(at: stagingDir)
            throw PythonEnvironmentError.moduleValidationFailed(
                unitID: unitID,
                module: module,
                detail: validateResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        // 9. Atomic promote: staging → final
        if fileManager.fileExists(atPath: venvDir.path) {
            try fileManager.removeItem(at: venvDir)
        }
        try fileManager.moveItem(at: stagingDir, to: venvDir)
        log.info("[prepare] Venv ready at \(venvDir.path)")

        return PythonEnvironmentResult(
            unitID: unitID,
            venvDirectory: venvDir,
            pythonPath: venvPython,
            package: pythonConfig.package,
            version: pythonConfig.version,
            wasCached: false
        )
    }

    /// Remove a Python environment for a unit entirely.
    ///
    /// Deletes the `<basePath>/Installed/python/<unitID>/` directory tree.
    public func remove(unitID: String, basePath: URL) throws {
        let unitRoot = pythonUnitRoot(unitID: unitID, basePath: basePath)
        if fileManager.fileExists(atPath: unitRoot.path) {
            log.info("[remove] Removing Python environment: \(unitRoot.path)")
            try fileManager.removeItem(at: unitRoot)
        }
    }

    // MARK: - Path Helpers

    /// The root directory for a Python unit's environment:
    /// `<basePath>/Installed/python/<unitID>/`
    public func pythonUnitRoot(unitID: String, basePath: URL) -> URL {
        basePath
            .appendingPathComponent("Installed")
            .appendingPathComponent("python")
            .appendingPathComponent(unitID)
    }

    /// The venv directory for a Python unit:
    /// `<basePath>/Installed/python/<unitID>/venv/`
    public func venvDirectory(unitID: String, basePath: URL) -> URL {
        pythonUnitRoot(unitID: unitID, basePath: basePath)
            .appendingPathComponent("venv")
    }

    // MARK: - Private

    private func findSystemPython() throws -> String {
        for path in Self.pythonSearchPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        throw PythonEnvironmentError.pythonNotFound
    }

    private func isVenvValid(
        venvDirectory: URL,
        pythonConfig: RuntimeUnit.PythonConfig
    ) -> Bool {
        let python = venvDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent("python3")

        guard fileManager.isExecutableFile(atPath: python.path) else {
            return false
        }

        // Check the module is importable
        let result = try? commandRunner.run(
            executable: python.path,
            arguments: ["-c", "import \(pythonConfig.entrypoint.module)"],
            environment: [
                "VIRTUAL_ENV": venvDirectory.path,
                "PATH": "\(venvDirectory.appendingPathComponent("bin").path):/usr/bin:/bin",
            ]
        )
        return result?.exitCode == 0
    }
}
