import HavenCore

/// Jellyfin service spec defined as native Swift.
///
/// This replaces the JSON catalog files for Jellyfin. The version is
/// currently hardcoded — a future update mechanism should query
/// upstream for the latest release and refresh the artifact version.
extension BuiltInCatalog {

    static let jellyfin: (Capability, HavenCore.Bundle, [RuntimeUnit]) = {
        let capability = Capability(
            id: "haven.capability.jellyfin",
            name: "Jellyfin",
            version: "10.10.6",
            description: "Your personal streaming server for movies and TV shows.",
            icon: "film",
            fullDescription: """
            Jellyfin is the free software media system that puts you in control of managing \
            and streaming your media. Stream to any device from your own server with no strings \
            attached — no central server, no tracking, and no hidden fees.

            Key features:
            • Stream movies and TV shows to any device
            • Automatic metadata, artwork, and subtitle downloading
            • Live TV and DVR support
            • Multi-user with parental controls
            • Hardware-accelerated transcoding
            • Apps for every platform — TV, mobile, desktop, and web
            • Completely free and open source
            """,
            notes: ["Movies", "TV Shows", "Streaming"],
            iconImage: "https://raw.githubusercontent.com/jellyfin/jellyfin-ux/master/branding/SVG/icon-transparent.svg",
            screenshots: [
                "https://jellyfin.org/images/screenshots/home_full.png",
                "https://jellyfin.org/images/screenshots/movie_full.png",
            ]
        )

        let bundle = HavenCore.Bundle(
            id: "haven.bundle.jellyfin-basic",
            name: "Jellyfin",
            capability: "haven.capability.jellyfin",
            runtimeUnits: ["haven.unit.jellyfin"],
            settings: [
                SettingField(
                    key: "movies_path",
                    label: "Movies folder",
                    fieldType: .path,
                    defaultValue: "~/Movies",
                    required: true
                ),
                SettingField(
                    key: "port",
                    label: "Port",
                    fieldType: .integer,
                    defaultValue: "8096"
                ),
            ],
            onboarding: Onboarding(steps: [
                OnboardingStep(
                    type: .info,
                    title: "Your movie server is ready",
                    body: "Jellyfin is now running on your Mac. It will start automatically whenever your Mac is on."
                ),
                OnboardingStep(
                    type: .info,
                    title: "Add your movies",
                    body: "Point Jellyfin at your movies folder and it will automatically download metadata, artwork, and subtitles.",
                    fields: [
                        OnboardingField(label: "Movies folder", value: "${content_dir}")
                    ]
                ),
                OnboardingStep(
                    type: .info,
                    title: "Watch anywhere",
                    body: "Use the Jellyfin app on your TV, phone, or tablet to stream your movies.",
                    fields: [
                        OnboardingField(label: "Server address", value: "http://your-mac:${port}")
                    ]
                ),
            ]),
            storage: [
                "data":    StoragePolicy(persistent: true, userVisible: false),
                "config":  StoragePolicy(persistent: true, userVisible: false),
                "cache":   StoragePolicy(persistent: false, userVisible: false),
                "logs":    StoragePolicy(persistent: false, userVisible: false),
                "content": StoragePolicy(persistent: true, userVisible: true),
            ]
        )

        let runtimeUnit = RuntimeUnit(
            id: "haven.unit.jellyfin",
            bundleID: "haven.bundle.jellyfin-basic",
            runtimeType: .native,
            installSource: "",
            launchArguments: [
                "--datadir", "${data_dir}",
                "--configdir", "${config_dir}",
                "--cachedir", "${cache_dir}",
                "--logdir", "${logs_dir}",
                "--ffmpeg", "/opt/homebrew/bin/ffmpeg",
            ],
            healthcheck: Healthcheck(
                type: .http,
                target: "http://localhost:${port}/System/Ping",
                intervalSeconds: 15,
                retries: 3
            ),
            port: 8096,
            environment: [
                "JELLYFIN_LOG_DIR": "${logs_dir}",
            ],
            entrypoint: RuntimeUnit.Entrypoint(command: "jellyfin"),
            artifact: Artifact(
                type: .githubRelease,
                repo: "jellyfin/jellyfin",
                version: "v10.10.6",
                assets: [
                    ArtifactAsset(os: "macos", arch: "arm64", file: "jellyfin-server_10.10.6_portable_macos-arm64.tar.gz"),
                    ArtifactAsset(os: "macos", arch: "x86_64", file: "jellyfin-server_10.10.6_portable_macos-amd64.tar.gz"),
                    ArtifactAsset(os: "linux", arch: "amd64", file: "jellyfin-server_10.10.6_portable_linux-amd64.tar.gz"),
                ],
                archive: ArtifactArchive(format: "tar.gz", stripFirstDirectory: true)
            ),
            directories: [
                "data":    "data",
                "config":  "config",
                "cache":   "cache",
                "logs":    "logs",
                "content": "${movies_path}",
            ],
            install: InstallBlock(steps: [
                InstallStep(action: .mkdir, path: "${data_dir}"),
                InstallStep(action: .mkdir, path: "${config_dir}"),
                InstallStep(action: .mkdir, path: "${logs_dir}"),
                InstallStep(action: .mkdir, path: "${cache_dir}"),
                InstallStep(action: .mkdir, path: "${content_dir}"),
            ]),
            dependencies: [
                Dependency(
                    id: "ffmpeg",
                    kind: .helperBinary,
                    required: false,
                    validateCommand: "/opt/homebrew/bin/ffmpeg -version",
                    description: "Enables video transcoding to different formats and resolutions."
                ),
            ]
        )

        return (capability, bundle, [runtimeUnit])
    }()
}
