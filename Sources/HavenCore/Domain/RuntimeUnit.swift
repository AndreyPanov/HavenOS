import Foundation

/// One launchable service or process that implements part or all of a bundle.
///
/// A RuntimeUnit is the running instance of a bundle component. It owns
/// the lifecycle (start / stop) and is managed by a runtime adapter
/// (see `HavenRuntimes`).
///
/// Example: `"test-web"` is a runtime unit — a web server process
/// that depends on a worker and a database.
public struct RuntimeUnit: Identifiable, Codable, Equatable, Sendable {

    /// The execution environment for the unit.
    public enum RuntimeType: String, Codable, Equatable, Sendable {
        /// A native macOS binary launched directly.
        case native
        /// A Python application managed by Haven's built-in Python adapter.
        case python
    }

    /// Plugin-friendly entrypoint block that maps to launchArguments/environment.
    /// `command` is ignored (Haven uses `installSource`).
    /// `args` maps to `launchArguments`.
    /// `env` maps to `environment`.
    private struct Entrypoint: Codable, Equatable {
        let command: String?
        let args: [String]?
        let env: [String: String]?
    }

    /// Unique identifier, e.g. `"haven.unit.test-web"`.
    public let id: String

    /// ID of the bundle this unit belongs to.
    public let bundleID: String

    /// How this unit is executed.
    public let runtimeType: RuntimeType

    /// Path or image reference used to install / pull the unit.
    /// For `native` this is a filesystem path; for `python` a package or script path.
    public let installSource: String

    /// Command and arguments used to launch the unit.
    /// Can be populated from the `"entrypoint"` block (entrypoint takes precedence).
    public let launchArguments: [String]

    /// Optional healthcheck definition.
    public let healthcheck: Healthcheck?

    /// IDs of other runtime units that must start before this one.
    public let dependsOn: [String]

    /// Fixed port this unit listens on, if any.
    public let port: Int?

    /// Environment variables to set when launching. Values may contain
    /// `${setting_key}` placeholders that the planner expands.
    /// Can be populated from the `"entrypoint"` block (entrypoint takes precedence).
    public let environment: [String: String]

    /// Optional version string for the runtime unit.
    public let version: String?

    /// Optional artifact descriptor for automatic binary fetching.
    /// When present, Haven downloads the binary during install instead
    /// of requiring a pre-existing `installSource` path.
    public let artifact: Artifact?

    public init(
        id: String,
        bundleID: String,
        runtimeType: RuntimeType,
        installSource: String,
        launchArguments: [String],
        healthcheck: Healthcheck? = nil,
        dependsOn: [String] = [],
        port: Int? = nil,
        environment: [String: String] = [:],
        version: String? = nil,
        artifact: Artifact? = nil
    ) {
        self.id = id
        self.bundleID = bundleID
        self.runtimeType = runtimeType
        self.installSource = installSource
        self.launchArguments = launchArguments
        self.healthcheck = healthcheck
        self.dependsOn = dependsOn
        self.port = port
        self.environment = environment
        self.version = version
        self.artifact = artifact
    }

    // MARK: - Codable (entrypoint + version support)

    private enum CodingKeys: String, CodingKey {
        case id, bundleID, runtimeType, installSource
        case launchArguments, healthcheck, dependsOn, port
        case environment, entrypoint, version, artifact
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        runtimeType = try c.decode(RuntimeType.self, forKey: .runtimeType)
        artifact = try c.decodeIfPresent(Artifact.self, forKey: .artifact)

        // installSource is optional when artifact is present.
        installSource = try c.decodeIfPresent(String.self, forKey: .installSource) ?? ""

        let ep = try c.decodeIfPresent(Entrypoint.self, forKey: .entrypoint)

        // Entrypoint.args takes precedence over top-level launchArguments.
        if let epArgs = ep?.args {
            launchArguments = epArgs
        } else {
            launchArguments = try c.decodeIfPresent([String].self, forKey: .launchArguments) ?? []
        }

        // Entrypoint.env takes precedence over top-level environment.
        if let epEnv = ep?.env {
            environment = epEnv
        } else {
            environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        }

        healthcheck = try c.decodeIfPresent(Healthcheck.self, forKey: .healthcheck)
        dependsOn = try c.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        version = try c.decodeIfPresent(String.self, forKey: .version)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(bundleID, forKey: .bundleID)
        try c.encode(runtimeType, forKey: .runtimeType)
        try c.encode(installSource, forKey: .installSource)
        try c.encode(launchArguments, forKey: .launchArguments)
        try c.encodeIfPresent(healthcheck, forKey: .healthcheck)
        try c.encode(dependsOn, forKey: .dependsOn)
        try c.encodeIfPresent(port, forKey: .port)
        try c.encode(environment, forKey: .environment)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encodeIfPresent(artifact, forKey: .artifact)
    }

    /// Returns a copy with a different `installSource`, keeping all other fields.
    public func withInstallSource(_ newSource: String) -> RuntimeUnit {
        RuntimeUnit(
            id: id, bundleID: bundleID, runtimeType: runtimeType,
            installSource: newSource, launchArguments: launchArguments,
            healthcheck: healthcheck, dependsOn: dependsOn,
            port: port, environment: environment, version: version,
            artifact: artifact
        )
    }

    /// Validates that the unit has enough information to install and launch.
    ///
    /// - id and bundleID must be non-empty.
    /// - installSource must be non-empty unless `artifact` provides the source.
    /// - launchArguments must contain at least one element unless `artifact`
    ///   is present (the executable path is resolved at install time).
    /// - If a healthcheck is attached, it must validate independently.
    public func validate() throws {
        if id.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("RuntimeUnit id must not be empty.")
        }
        if bundleID.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("RuntimeUnit bundleID must not be empty.")
        }
        if installSource.trimmingCharacters(in: .whitespaces).isEmpty && artifact == nil {
            throw ValidationError("RuntimeUnit installSource must not be empty when no artifact is provided.")
        }
        if launchArguments.isEmpty && artifact == nil {
            throw ValidationError("RuntimeUnit launchArguments must not be empty.")
        }
        try healthcheck?.validate()
    }
}

// MARK: - Examples

extension RuntimeUnit {
    /// Example: a database runtime unit with no dependencies.
    public static let testDBExample = RuntimeUnit(
        id: "haven.unit.test-db",
        bundleID: "haven.bundle.test-library-basic",
        runtimeType: .native,
        installSource: "/opt/haven/bin/test-db",
        launchArguments: [
            "/opt/haven/bin/test-db",
            "--datadir", "${data_dir}/db",
        ],
        healthcheck: Healthcheck(
            type: .tcp,
            target: "localhost:5432",
            intervalSeconds: 10,
            retries: 3
        ),
        environment: [
            "DB_DATA": "${data_path}",
        ]
    )

    /// Example: a worker runtime unit that depends on the database.
    public static let testWorkerExample = RuntimeUnit(
        id: "haven.unit.test-worker",
        bundleID: "haven.bundle.test-library-basic",
        runtimeType: .native,
        installSource: "/opt/haven/bin/test-worker",
        launchArguments: [
            "/opt/haven/bin/test-worker",
            "--config", "${config_dir}/worker.toml",
        ],
        dependsOn: ["haven.unit.test-db"],
        environment: [
            "WORKER_DATA": "${data_path}",
            "WORKER_LOGS": "${logs_dir}",
        ]
    )

    /// Example: a web server runtime unit that depends on the worker.
    public static let testWebExample = RuntimeUnit(
        id: "haven.unit.test-web",
        bundleID: "haven.bundle.test-library-basic",
        runtimeType: .native,
        installSource: "/opt/haven/bin/test-web",
        launchArguments: [
            "/opt/haven/bin/test-web",
            "--port", "${port}",
        ],
        healthcheck: Healthcheck(
            type: .http,
            target: "http://localhost:${port}/health",
            intervalSeconds: 15,
            retries: 3
        ),
        dependsOn: ["haven.unit.test-worker"],
        port: 8080,
        environment: [
            "WEB_PORT": "${port}",
            "WEB_DATA": "${data_path}",
            "WEB_LOGS": "${logs_dir}",
        ]
    )
}
