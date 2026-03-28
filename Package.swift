// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Haven",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
    ],
    targets: [
        // MARK: - Core

        .target(
            name: "HavenCore",
            dependencies: [],
            path: "Sources/HavenCore"
        ),

        // MARK: - Executor

        .target(
            name: "HavenExecutor",
            dependencies: ["HavenCore", "HavenRuntimes", "HavenLaunchd"],
            path: "Sources/HavenExecutor"
        ),

        // MARK: - CLI (library + thin executable)

        /// All command definitions live here so they are importable by tests.
        .target(
            name: "HavenCLIKit",
            dependencies: [
                "HavenCore",
                "HavenExecutor",
                "HavenLaunchd",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/HavenCLIKit"
        ),

        /// Thin entry point — calls `Havenctl.main()`.
        .executableTarget(
            name: "HavenCLI",
            dependencies: ["HavenCLIKit"],
            path: "Sources/HavenCLI"
        ),

        // MARK: - Launchd modeling

        .target(
            name: "HavenLaunchd",
            dependencies: ["HavenCore", "HavenRuntimes"],
            path: "Sources/HavenLaunchd"
        ),

        // MARK: - Runtime adapters

        .target(
            name: "HavenRuntimes",
            dependencies: ["HavenCore"],
            path: "Sources/HavenRuntimes"
        ),

        // MARK: - Artifact installer

        .target(
            name: "HavenInstaller",
            dependencies: ["HavenCore"],
            path: "Sources/HavenInstaller"
        ),

        // MARK: - Tests

        .testTarget(
            name: "HavenCoreTests",
            dependencies: ["HavenCore"],
            path: "Tests/HavenCoreTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "HavenRuntimesTests",
            dependencies: ["HavenRuntimes"],
            path: "Tests/HavenRuntimesTests"
        ),
        .testTarget(
            name: "HavenLaunchdTests",
            dependencies: ["HavenLaunchd", "HavenRuntimes"],
            path: "Tests/HavenLaunchdTests"
        ),
        .testTarget(
            name: "HavenInstallerTests",
            dependencies: ["HavenInstaller"],
            path: "Tests/HavenInstallerTests"
        ),
        .testTarget(
            name: "HavenExecutorTests",
            dependencies: ["HavenExecutor", "HavenLaunchd", "HavenRuntimes"],
            path: "Tests/HavenExecutorTests"
        ),
        .testTarget(
            name: "HavenCLITests",
            dependencies: [
                "HavenCLIKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tests/HavenCLITests"
        ),
    ]
)
