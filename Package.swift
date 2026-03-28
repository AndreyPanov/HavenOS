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

        // MARK: - CLI (library + thin executable)

        /// All command definitions live here so they are importable by tests.
        .target(
            name: "HavenCLIKit",
            dependencies: [
                "HavenCore",
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

        // MARK: - Launchd integration (stub)

        .target(
            name: "HavenLaunchd",
            dependencies: ["HavenCore"],
            path: "Sources/HavenLaunchd"
        ),

        // MARK: - Runtime adapters (stub)

        .target(
            name: "HavenRuntimes",
            dependencies: ["HavenCore"],
            path: "Sources/HavenRuntimes"
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
            name: "HavenCLITests",
            dependencies: [
                "HavenCLIKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tests/HavenCLITests"
        ),
    ]
)
