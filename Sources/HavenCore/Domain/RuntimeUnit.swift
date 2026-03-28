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
        case binary
        /// An OCI / Docker container.
        case container
        /// A script executed via an interpreter (bash, python, etc.).
        case script
    }

    /// Unique identifier, e.g. `"haven.unit.test-web"`.
    public let id: String

    /// ID of the bundle this unit belongs to.
    public let bundleID: String

    /// How this unit is executed.
    public let runtimeType: RuntimeType

    /// Path or image reference used to install / pull the unit.
    /// For `binary` this is a filesystem path; for `container` an image name.
    public let installSource: String

    /// Command and arguments used to launch the unit.
    public let launchArguments: [String]

    /// Optional healthcheck definition.
    public let healthcheck: Healthcheck?

    /// IDs of other runtime units that must start before this one.
    public let dependsOn: [String]

    /// Fixed port this unit listens on, if any.
    public let port: Int?

    /// Environment variables to set when launching. Values may contain
    /// `${setting_key}` placeholders that the planner expands.
    public let environment: [String: String]

    public init(
        id: String,
        bundleID: String,
        runtimeType: RuntimeType,
        installSource: String,
        launchArguments: [String],
        healthcheck: Healthcheck? = nil,
        dependsOn: [String] = [],
        port: Int? = nil,
        environment: [String: String] = [:]
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
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        runtimeType = try c.decode(RuntimeType.self, forKey: .runtimeType)
        installSource = try c.decode(String.self, forKey: .installSource)
        launchArguments = try c.decode([String].self, forKey: .launchArguments)
        healthcheck = try c.decodeIfPresent(Healthcheck.self, forKey: .healthcheck)
        dependsOn = try c.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
        port = try c.decodeIfPresent(Int.self, forKey: .port)
        environment = try c.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
    }

    /// Validates that the unit has enough information to install and launch.
    ///
    /// - id and bundleID must be non-empty.
    /// - installSource must be non-empty.
    /// - launchArguments must contain at least one element (the executable).
    /// - If a healthcheck is attached, it must validate independently.
    public func validate() throws {
        if id.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("RuntimeUnit id must not be empty.")
        }
        if bundleID.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("RuntimeUnit bundleID must not be empty.")
        }
        if installSource.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ValidationError("RuntimeUnit installSource must not be empty.")
        }
        if launchArguments.isEmpty {
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
        runtimeType: .binary,
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
        runtimeType: .binary,
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
        runtimeType: .binary,
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
