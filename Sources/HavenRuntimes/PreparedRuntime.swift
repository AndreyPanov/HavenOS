import Foundation
import HavenCore

/// A fully prepared runtime unit ready to be handed to a process launcher.
///
/// `PreparedRuntime` is the output of a `RuntimeAdapter.prepare()` call.
/// It contains everything needed to launch a process — executable path,
/// arguments, environment, working directory — without any knowledge of
/// _how_ that preparation happened.
///
/// This type is deliberately runtime-agnostic. Whether the unit is a
/// native binary or a Haven-managed Python app, the result looks the same
/// to the execution layer.
public struct PreparedRuntime: Equatable, Sendable {

    /// The runtime unit ID this preparation belongs to.
    public let unitID: String

    /// Absolute path to the executable that should be launched.
    public let executableURL: URL

    /// Arguments to pass to the executable (argv[0] should be the executable).
    public let arguments: [String]

    /// Environment variables for the launched process.
    public let environment: [String: String]

    /// Working directory for the launched process.
    public let workingDirectory: URL

    /// Directories owned by this runtime that must exist before launch.
    /// The execution layer should create these if they don't exist.
    public let managedDirectories: [URL]

    /// The runtime type that produced this preparation.
    public let runtimeType: RuntimeUnit.RuntimeType

    /// Resolved healthcheck, if any.
    public let healthcheck: Healthcheck?

    /// Assigned port, if any.
    public let port: Int?

    /// IDs of units that must be running before this one starts.
    public let dependsOn: [String]

    public init(
        unitID: String,
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL,
        managedDirectories: [URL],
        runtimeType: RuntimeUnit.RuntimeType,
        healthcheck: Healthcheck?,
        port: Int?,
        dependsOn: [String]
    ) {
        self.unitID = unitID
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.managedDirectories = managedDirectories
        self.runtimeType = runtimeType
        self.healthcheck = healthcheck
        self.port = port
        self.dependsOn = dependsOn
    }
}
