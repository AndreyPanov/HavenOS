import HavenCore

/// Navidrome service spec defined as native Swift.
///
/// This replaces the JSON catalog files for Navidrome. The version is
/// currently hardcoded — a future update mechanism should query
/// upstream for the latest release and refresh the artifact version.
extension BuiltInCatalog {

    static let navidrome: (Capability, HavenCore.Bundle, [RuntimeUnit]) = {
        let capability = Capability(
            id: "haven.capability.navidrome",
            name: "Navidrome",
            version: "0.61.2",
            description: "Personal music server and streamer compatible with Subsonic/Airsonic.",
            icon: "music.note.house",
            fullDescription: """
            Navidrome is a self-hosted, open-source music server and streamer. It gives you \
            freedom to listen to your music collection from any browser or mobile device.

            Fully compatible with the Subsonic API, Navidrome works with popular apps like \
            DSub, Symfonium, Amperfy, play:Sub, and many more.

            Key features:
            • Stream your entire music library from anywhere
            • Handles very large collections with ease
            • Multi-user support — each person gets their own playlists and favorites
            • Scrobble to Last.fm, ListenBrainz, and Maloja
            • Smart playlists and album/artist browsing
            • Transcoding on the fly — adapts to your connection speed
            • Low resource usage — runs great on a Mac mini
            """,
            notes: ["Music", "Streaming", "Subsonic"],
            iconImage: "https://raw.githubusercontent.com/navidrome/navidrome/master/resources/logo-192x192.png",
            screenshots: [
                "https://raw.githubusercontent.com/navidrome/navidrome/master/.github/screenshots/ss-desktop-player.png",
                "https://raw.githubusercontent.com/navidrome/navidrome/master/.github/screenshots/ss-mobile-album-view.png",
                "https://raw.githubusercontent.com/navidrome/navidrome/master/.github/screenshots/ss-mobile-player.png",
            ]
        )

        let bundle = HavenCore.Bundle(
            id: "haven.bundle.navidrome-basic",
            name: "Navidrome",
            capability: "haven.capability.navidrome",
            runtimeUnits: ["haven.unit.navidrome"],
            settings: [
                SettingField(
                    key: "music_path",
                    label: "Music library folder",
                    fieldType: .path,
                    defaultValue: "~/Music",
                    required: true
                ),
                SettingField(
                    key: "port",
                    label: "Port",
                    fieldType: .integer,
                    defaultValue: "4533"
                ),
            ],
            onboarding: Onboarding(steps: [
                OnboardingStep(
                    type: .info,
                    title: "Your music server is ready",
                    body: "Navidrome is now running on your Mac. It will start automatically whenever your Mac is on."
                ),
                OnboardingStep(
                    type: .info,
                    title: "Point it to your music",
                    body: "Navidrome is watching your Music folder. Any music files you add will appear automatically within a few minutes.",
                    fields: [
                        OnboardingField(label: "Music folder", value: "${content_dir}")
                    ]
                ),
                OnboardingStep(
                    type: .action,
                    title: "Create your account",
                    body: "Set up your admin username and password in your browser. You'll only need to do this once.",
                    url: "http://localhost:${port}"
                ),
                OnboardingStep(
                    type: .info,
                    title: "Listen anywhere",
                    body: "Use any Subsonic-compatible app to stream your music. Search for Substreamer, play:Sub, or Amperfy in your app store.",
                    fields: [
                        OnboardingField(label: "Server address", value: "http://your-mac.local:${port}")
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
            id: "haven.unit.navidrome",
            bundleID: "haven.bundle.navidrome-basic",
            runtimeType: .native,
            installSource: "",
            launchArguments: ["--configfile", "${config_dir}/navidrome.toml"],
            healthcheck: Healthcheck(
                type: .http,
                target: "http://localhost:${port}/ping",
                intervalSeconds: 15,
                retries: 3
            ),
            port: 4533,
            environment: [
                "ND_DATAFOLDER": "${data_dir}",
                "ND_MUSICFOLDER": "${content_dir}",
                "ND_PORT": "${port}",
            ],
            entrypoint: RuntimeUnit.Entrypoint(command: "navidrome"),
            artifact: Artifact(
                type: .githubRelease,
                repo: "navidrome/navidrome",
                version: "v0.61.2",
                assets: [
                    ArtifactAsset(os: "macos", arch: "arm64", file: "navidrome_0.61.2_darwin_arm64.tar.gz"),
                    ArtifactAsset(os: "macos", arch: "x86_64", file: "navidrome_0.61.2_darwin_amd64.tar.gz"),
                    ArtifactAsset(os: "linux", arch: "amd64", file: "navidrome_0.61.2_linux_amd64.tar.gz"),
                ],
                archive: ArtifactArchive(format: "tar.gz")
            ),
            directories: [
                "data":    "data",
                "config":  "config",
                "cache":   "cache",
                "logs":    "logs",
                "content": "${music_path}",
            ],
            install: InstallBlock(steps: [
                InstallStep(action: .mkdir, path: "${data_dir}"),
                InstallStep(action: .mkdir, path: "${config_dir}"),
                InstallStep(action: .mkdir, path: "${logs_dir}"),
                InstallStep(action: .mkdir, path: "${cache_dir}"),
                InstallStep(action: .mkdir, path: "${content_dir}"),
                InstallStep(action: .generateSecret, path: "session_key", content: "32", ifNotExists: true),
                InstallStep(
                    action: .writeFile,
                    path: "${config_dir}/navidrome.toml",
                    content: """
                    MusicFolder = "${content_dir}"
                    DataFolder = "${data_dir}"
                    CacheFolder = "${cache_dir}"
                    LogFile = "${logs_dir}/navidrome.log"
                    Port = ${port}
                    SessionSecret = "${session_key}"
                    ScanSchedule = "@every 5m"
                    TranscodingCacheSize = "512MB"
                    """,
                    ifNotExists: true
                ),
                InstallStep(action: .chmod, path: "${config_dir}/navidrome.toml", mode: "600"),
            ]),
            dependencies: [
                Dependency(
                    id: "ffmpeg",
                    kind: .helperBinary,
                    required: false,
                    validateCommand: "/opt/homebrew/bin/ffmpeg -version",
                    description: "Enables audio transcoding to different formats."
                ),
            ]
        )

        return (capability, bundle, [runtimeUnit])
    }()
}
