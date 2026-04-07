import Foundation

/// Result of a successful Python environment preparation.
public struct PythonEnvironmentResult: Equatable, Sendable {

    /// The runtime unit ID.
    public let unitID: String

    /// The venv directory path.
    public let venvDirectory: URL

    /// Path to the venv's python3 interpreter.
    public let pythonPath: URL

    /// The installed package name.
    public let package: String

    /// The installed version.
    public let version: String

    /// Whether an existing valid venv was reused.
    public let wasCached: Bool

    public init(
        unitID: String,
        venvDirectory: URL,
        pythonPath: URL,
        package: String,
        version: String,
        wasCached: Bool
    ) {
        self.unitID = unitID
        self.venvDirectory = venvDirectory
        self.pythonPath = pythonPath
        self.package = package
        self.version = version
        self.wasCached = wasCached
    }
}
