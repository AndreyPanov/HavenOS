import Foundation

/// Errors from Python environment preparation.
///
/// Error case names use service-oriented language. Tooling details
/// (pip, venv, etc.) are captured in the `detail` field for diagnostics.
public enum PythonEnvironmentError: Error, LocalizedError, Equatable, Sendable {

    /// No Python 3 interpreter was found at any well-known location.
    case pythonNotFound

    /// Virtual environment creation failed.
    case venvCreationFailed(unitID: String, detail: String)

    /// Package installation via pip failed.
    case packageInstallFailed(unitID: String, package: String, detail: String)

    /// The specified module could not be imported after installation.
    case moduleValidationFailed(unitID: String, module: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            "Python 3 is required but was not found on this system."
        case .venvCreationFailed(_, let detail):
            "Failed to create runtime environment: \(detail)"
        case .packageInstallFailed(_, let package, let detail):
            "Failed to install package '\(package)': \(detail)"
        case .moduleValidationFailed(_, let module, let detail):
            "Module '\(module)' could not be loaded after installation: \(detail)"
        }
    }
}
