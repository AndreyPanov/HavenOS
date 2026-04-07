import Foundation

/// Persisted metadata about an installed Python environment for a runtime unit.
///
/// Records which package, version, and venv location were used so that
/// Haven can detect broken environments and support reinstall/upgrade.
public struct StoredPythonInfo: Codable, Equatable, Sendable {

    /// The runtime unit ID this environment was created for.
    public let unitID: String

    /// The PyPI package name (e.g. `"calibreweb"`).
    public let package: String

    /// The pinned version that was installed (e.g. `"0.6.26"`).
    public let version: String

    /// The Python module entrypoint (e.g. `"cps"`).
    public let module: String

    /// The filesystem path to the virtual environment directory.
    public let venvDirectory: String

    /// The filesystem path to the venv's python3 interpreter.
    public let pythonPath: String

    public init(
        unitID: String,
        package: String,
        version: String,
        module: String,
        venvDirectory: String,
        pythonPath: String
    ) {
        self.unitID = unitID
        self.package = package
        self.version = version
        self.module = module
        self.venvDirectory = venvDirectory
        self.pythonPath = pythonPath
    }
}
