import ArgumentParser
import Foundation
import HavenCore
import HavenExecutor
import HavenInstaller
import HavenLaunchd

public struct Havenctl: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "havenctl",
        abstract: "Haven control utility — manage services and runtime units.",
        version: "0.1.0",
        subcommands: [
            InstallCommand.self,
            UninstallCommand.self,
            StartCommand.self,
            StopCommand.self,
            StatusCommand.self,
            ListCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )

    public init() {}
}

// MARK: - Shared Options

struct CommonOptions: ParsableArguments {
    @Option(name: .long, help: "Base directory for Haven data.")
    var baseDir: String = "~/.haven"

    func resolvedBaseURL() -> URL {
        let expanded = NSString(string: baseDir).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    func makeExecutor() -> HavenExecutor {
        let base = resolvedBaseURL()
        let paths = HavenPaths(base: base)
        let stateStore = FileStateStore(paths: paths)
        let launchdController = LaunchdController()
        let artifactInstaller = ArtifactInstaller(paths: paths)
        return HavenExecutor(
            paths: paths,
            stateStore: stateStore,
            launchdController: launchdController,
            artifactInstaller: artifactInstaller
        )
    }

    func makeStateStore() -> FileStateStore {
        let base = resolvedBaseURL()
        let paths = HavenPaths(base: base)
        return FileStateStore(paths: paths)
    }
}

// MARK: - install

public struct InstallCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install a capability and its runtime units."
    )

    @Argument(help: "The capability ID to install.")
    var capabilityID: String

    @Option(name: .long, help: "Directory containing spec files.")
    var specsDir: String = "~/.haven/Specs"

    @Option(name: .long, parsing: .singleValue, help: "Setting override (key=value).")
    var set: [String] = []

    @OptionGroup var common: CommonOptions

    public init() {}

    public func run() throws {
        // Parse key=value settings
        var settings: [String: String] = [:]
        for pair in set {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                print("Invalid setting format '\(pair)'. Use key=value.")
                throw ExitCode.failure
            }
            let key = String(parts[0])
            let value = String(parts[1])
            settings[key] = value
        }

        // Load specs
        let specsURL = URL(
            fileURLWithPath: NSString(string: specsDir).expandingTildeInPath
        )
        let loadResult = SpecLoader.load(from: specsURL)
        guard loadResult.succeeded, let registry = loadResult.registry else {
            print("Failed to load specs from \(specsURL.path):")
            for issue in loadResult.issues {
                print("  - \(issue)")
            }
            throw ExitCode.failure
        }

        let executor = common.makeExecutor()
        let state = try executor.install(
            capabilityID: capabilityID,
            registry: registry,
            settings: settings
        )

        print("Installed \(capabilityID)")
        print("  Bundle: \(state.bundleID)")
        print("  Units:  \(state.runtimeUnitIDs.joined(separator: ", "))")
        if !state.portAssignments.isEmpty {
            let ports = state.portAssignments
                .map { "\($0.unitID):\($0.port)" }
                .joined(separator: ", ")
            print("  Ports:  \(ports)")
        }
        print("  Status: \(state.status.rawValue)")
    }
}

// MARK: - uninstall

public struct UninstallCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Uninstall a capability and remove its runtime units."
    )

    @Argument(help: "The capability ID to uninstall.")
    var capabilityID: String

    @OptionGroup var common: CommonOptions

    public init() {}

    public func run() throws {
        let executor = common.makeExecutor()
        try executor.uninstall(capabilityID: capabilityID)
        print("Uninstalled \(capabilityID)")
    }
}

// MARK: - start

public struct StartCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Start all units for an installed service."
    )

    @Argument(help: "The capability ID to start.")
    var capabilityID: String

    @OptionGroup var common: CommonOptions

    public init() {}

    public func run() throws {
        let executor = common.makeExecutor()
        try executor.start(capabilityID: capabilityID)
        print("Started \(capabilityID)")
    }
}

// MARK: - stop

public struct StopCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop all units for a running service."
    )

    @Argument(help: "The capability ID to stop.")
    var capabilityID: String

    @OptionGroup var common: CommonOptions

    public init() {}

    public func run() throws {
        let executor = common.makeExecutor()
        try executor.stop(capabilityID: capabilityID)
        print("Stopped \(capabilityID)")
    }
}

// MARK: - status

public struct StatusCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the status of an installed service."
    )

    @Argument(help: "The capability ID to query.")
    var capabilityID: String

    @OptionGroup var common: CommonOptions

    public init() {}

    public func run() throws {
        let executor = common.makeExecutor()
        let report = try executor.status(capabilityID: capabilityID)

        print("Service: \(report.capabilityID)")
        print("  Bundle: \(report.bundleID)")
        print("  Status: \(report.status.rawValue)")
        print("  Units:")
        for unit in report.unitStatuses {
            let stateStr: String
            switch unit.state {
            case .running: stateStr = "running (pid \(unit.pid ?? 0))"
            case .stopped: stateStr = "stopped"
            case .installed: stateStr = "installed"
            case .notFound: stateStr = "not found"
            }
            var line = "    \(unit.unitID): \(stateStr)"
            if let exit = unit.lastExitStatus {
                line += " [exit: \(exit)]"
            }
            print(line)
        }
    }
}

// MARK: - list

public struct ListCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all installed services."
    )

    @OptionGroup var common: CommonOptions

    public init() {}

    public func run() throws {
        let stateStore = common.makeStateStore()
        let state = try stateStore.load()

        if state.services.isEmpty {
            print("No services installed.")
            return
        }

        for (_, service) in state.services.sorted(by: { $0.key < $1.key }) {
            let units = service.runtimeUnitIDs.joined(separator: ", ")
            print("\(service.capabilityID)  [\(service.status.rawValue)]  bundle=\(service.bundleID)  units=\(units)")
        }
    }
}
