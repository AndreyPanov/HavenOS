import ArgumentParser
import HavenCore

public struct Havenctl: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "havenctl",
        abstract: "Haven control utility — manage bundles and runtime units.",
        version: "0.1.0",
        subcommands: [
            StatusCommand.self,
            ListCommand.self,
        ],
        defaultSubcommand: StatusCommand.self
    )

    public init() {}
}

// MARK: - status

public struct StatusCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the overall Haven status."
    )

    public init() {}

    public func run() throws {
        print("Haven v0.1.0 — status: idle")
        print("No bundles loaded.")
    }
}

// MARK: - list

public struct ListCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List registered bundles and their runtime units."
    )

    @Flag(name: .shortAndLong, help: "Show full capability details.")
    public var verbose = false

    public init() {}

    public func run() throws {
        // Placeholder — real implementation will query HavenCore registries.
        let example = Bundle(
            id: "com.example.demo",
            name: "Demo Bundle",
            capabilities: [
                Capability(id: "cap.echo", name: "Echo", version: "1.0.0"),
            ]
        )
        print("Bundle: \(example.name) [\(example.id)]")
        if verbose {
            for cap in example.capabilities {
                print("  Capability: \(cap.name) v\(cap.version) [\(cap.id)]")
            }
        }
    }
}
