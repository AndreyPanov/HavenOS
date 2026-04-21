import HavenCore

/// Kavita service spec defined as native Swift.
///
/// This replaces the JSON catalog files for Kavita. The version is
/// currently hardcoded — a future update mechanism should query
/// upstream for the latest release and refresh the artifact version.
extension BuiltInCatalog {

    static let kavita: (Capability, HavenCore.Bundle, [RuntimeUnit]) = {
        let capability = Capability(
            id: "haven.capability.kavita",
            name: "Kavita",
            version: "0.8.9.1",
            description: "Your personal library for books, comics, and manga.",
            icon: "books.vertical",
            fullDescription: """
            Kavita is a fast, feature-rich, cross-platform reading server. It supports \
            a wide range of file formats for books, comics, and manga — all accessible \
            from a beautiful web interface.

            Key features:
            • Supports EPUB, PDF, CBZ, CBR, CB7, ZIP, RAR, and many more formats
            • Manga and comic reader with webtoon and continuous scroll modes
            • Book reader with customizable fonts, themes, and layout
            • Rich metadata support — automatic series grouping and cover detection
            • User management with per-library access controls
            • Reading progress synced across all your devices
            • OPDS support for third-party reading apps
            • Smart filters and collections to organize your library
            • Server-side search across your entire collection
            """,
            notes: ["Books", "Comics", "Manga", "Library"]
        )

        let bundle = HavenCore.Bundle(
            id: "haven.bundle.kavita-basic",
            name: "Kavita (Basic)",
            capability: "haven.capability.kavita",
            runtimeUnits: ["haven.unit.kavita"],
            settings: [
                SettingField(
                    key: "library_path",
                    label: "Library folder",
                    fieldType: .path,
                    defaultValue: "~/Books",
                    required: true
                ),
                SettingField(
                    key: "port",
                    label: "Port",
                    fieldType: .integer,
                    defaultValue: "5001"
                ),
            ],
            onboarding: Onboarding(steps: [
                OnboardingStep(
                    type: .info,
                    title: "Your library is ready",
                    body: "Kavita organizes your books, comics, and manga into a beautiful reading library you can access from any device.",
                    fields: [
                        OnboardingField(label: "Library folder", value: "${content_dir}")
                    ]
                ),
                OnboardingStep(
                    type: .action,
                    title: "Set up your account",
                    body: "Open Kavita to create your admin account and add your library folder. Kavita will scan your files and build your collection automatically.",
                    url: "http://localhost:${port}"
                ),
                OnboardingStep(
                    type: .info,
                    title: "Read from anywhere",
                    body: "Open a browser on any device to start reading. Kavita has a built-in reader for books, comics, and manga.",
                    fields: [
                        OnboardingField(label: "Address", value: "http://your-mac:${port}")
                    ]
                ),
            ]),
            storage: [
                "config":  StoragePolicy(persistent: true, userVisible: false),
                "data":    StoragePolicy(persistent: true, userVisible: false),
                "content": StoragePolicy(persistent: true, userVisible: true),
            ]
        )

        let runtimeUnit = RuntimeUnit(
            id: "haven.unit.kavita",
            bundleID: "haven.bundle.kavita-basic",
            runtimeType: .native,
            installSource: "",
            launchArguments: [],
            healthcheck: Healthcheck(
                type: .http,
                target: "http://localhost:${port}/api/health",
                intervalSeconds: 15,
                retries: 3
            ),
            port: 5001,
            entrypoint: RuntimeUnit.Entrypoint(command: "Kavita"),
            artifact: Artifact(
                type: .githubRelease,
                repo: "Kareadita/Kavita",
                version: "v0.8.9.1",
                assets: [
                    ArtifactAsset(os: "macos", arch: "arm64", file: "kavita-osx-arm64.tar.gz"),
                    ArtifactAsset(os: "macos", arch: "x86_64", file: "kavita-osx-x64.tar.gz"),
                    ArtifactAsset(os: "linux", arch: "amd64", file: "kavita-linux-x64.tar.gz"),
                ],
                archive: ArtifactArchive(format: "tar.gz", stripFirstDirectory: true)
            ),
            directories: [
                "config":  "config",
                "data":    "data",
                "content": "${library_path}",
            ],
            install: InstallBlock(steps: [
                InstallStep(action: .mkdir, path: "${config_dir}"),
                InstallStep(action: .mkdir, path: "${data_dir}"),
                InstallStep(action: .mkdir, path: "${content_dir}"),
                InstallStep(action: .generateSecret, path: "token_key", content: "64", ifNotExists: true),
                InstallStep(
                    action: .writeFile,
                    path: "${config_dir}/appsettings.json",
                    content: """
                    {
                      "TokenKey": "${token_key}",
                      "Port": ${port},
                      "IpAddresses": "",
                      "BaseUrl": "/",
                      "Cache": 75
                    }
                    """,
                    ifNotExists: true
                ),
                InstallStep(action: .chmod, path: "${config_dir}/appsettings.json", mode: "600"),
            ])
        )

        return (capability, bundle, [runtimeUnit])
    }()
}
