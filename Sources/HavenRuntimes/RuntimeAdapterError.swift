import Foundation

/// Errors that can occur during runtime preparation or teardown.
///
/// These errors use service-oriented language. Upper layers should
/// never need to translate these into user-visible messages that
/// mention tooling details (pip, python, PATH, etc.).
public enum RuntimeAdapterError: Error, Equatable {
    /// The install source path is missing or empty.
    case missingInstallSource(unitID: String)

    /// The executable could not be located at the expected path.
    case executableNotFound(unitID: String, path: String)

    /// No launch arguments were provided.
    case missingLaunchArguments(unitID: String)

    /// The runtime type is not supported by any registered adapter.
    case unsupportedRuntimeType(unitID: String, runtimeType: String)

    /// The runtime environment could not be created.
    case environmentSetupFailed(unitID: String, reason: String)
}
