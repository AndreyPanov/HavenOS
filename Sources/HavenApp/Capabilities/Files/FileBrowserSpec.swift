import HavenCore

/// File Browser service spec defined as native Swift.
///
/// Files is the first capability where unauthenticated LAN access would be a
/// serious footgun, so the built-in spec deliberately avoids `--noauth`.
/// Haven provides a managed username/password during installation.
extension BuiltInCatalog {

    static let filebrowser: (Capability, HavenCore.Bundle, [RuntimeUnit]) = {
        let capability = Capability(
            id: "haven.capability.filebrowser",
            name: "File Browser",
            version: "2.63.2",
            description: "Access and manage selected files from Haven and from a browser on your network.",
            icon: "folder",
            fullDescription: """
            File Browser provides browser-based file access for a selected folder on your Mac. \
            Haven keeps the local experience native while File Browser handles secure access \
            from phones, tablets, and other computers on your home network.

            Key features:
            • Browse and manage a selected folder
            • Upload and download files from another device
            • Create, rename, and delete files through a browser
            • Built-in text editor and media preview
            • Lightweight single binary — minimal resource usage
            • Haven-managed credentials instead of unauthenticated LAN access
            """,
            notes: ["Files", "Storage", "Browser Access"],
            iconImage: "https://raw.githubusercontent.com/filebrowser/filebrowser/master/branding/icon.png",
            screenshots: [
                "https://raw.githubusercontent.com/filebrowser/filebrowser/master/branding/banner.png",
            ]
        )

        let bundle = HavenCore.Bundle(
            id: "haven.bundle.filebrowser-basic",
            name: "Files",
            capability: "haven.capability.filebrowser",
            runtimeUnits: ["haven.unit.filebrowser"],
            settings: [
                SettingField(
                    key: "root_path",
                    label: "Files folder",
                    fieldType: .path,
                    defaultValue: "~/Documents",
                    required: true
                ),
                SettingField(
                    key: "port",
                    label: "Port",
                    fieldType: .integer,
                    defaultValue: "8080"
                ),
                SettingField(
                    key: "files_username",
                    label: "Managed username",
                    fieldType: .string,
                    defaultValue: "haven",
                    required: true,
                    sensitive: true
                ),
                SettingField(
                    key: "files_password",
                    label: "Managed password",
                    fieldType: .string,
                    required: true,
                    sensitive: true
                ),
            ],
            onboarding: Onboarding(steps: [
                OnboardingStep(
                    type: .info,
                    title: "Your file access is ready",
                    body: "Haven is serving only the folder you selected. Use the Files tab for native browsing or open File Browser from another device."
                ),
                OnboardingStep(
                    type: .info,
                    title: "Selected folder",
                    body: "This is the folder Haven exposes for file access.",
                    fields: [
                        OnboardingField(label: "Folder", value: "${content_dir}")
                    ]
                ),
                OnboardingStep(
                    type: .action,
                    title: "Open File Browser",
                    body: "Use Haven-managed credentials when opening from another device.",
                    url: "http://localhost:${port}"
                ),
            ]),
            storage: [
                "data": StoragePolicy(persistent: true, userVisible: false),
            ]
        )

        let runtimeUnit = RuntimeUnit(
            id: "haven.unit.filebrowser",
            bundleID: "haven.bundle.filebrowser-basic",
            runtimeType: .native,
            installSource: "",
            launchArguments: [
                "--address", "0.0.0.0",
                "--port", "${port}",
                "--root", "${content_dir}",
                "--database", "${data_dir}/filebrowser.db",
                "--disableExec",
            ],
            healthcheck: Healthcheck(
                type: .http,
                target: "http://localhost:${port}/health",
                intervalSeconds: 10,
                retries: 3
            ),
            port: 8080,
            entrypoint: RuntimeUnit.Entrypoint(command: "filebrowser"),
            artifact: Artifact(
                type: .githubRelease,
                repo: "filebrowser/filebrowser",
                version: "v2.63.2",
                assets: [
                    ArtifactAsset(os: "macos", arch: "arm64", file: "darwin-arm64-filebrowser.tar.gz"),
                    ArtifactAsset(os: "macos", arch: "x86_64", file: "darwin-amd64-filebrowser.tar.gz"),
                    ArtifactAsset(os: "linux", arch: "amd64", file: "linux-amd64-filebrowser.tar.gz"),
                ],
                archive: ArtifactArchive(format: "tar.gz")
            ),
            directories: [
                "data": "data",
                "content": "${data_dir}/served-roots",
            ],
            install: InstallBlock(steps: [
                InstallStep(action: .mkdir, path: "${data_dir}"),
                InstallStep(action: .mkdir, path: "${content_dir}"),
                InstallStep(action: .mkdir, path: "${root_path}"),
                InstallStep(
                    action: .symlink,
                    path: "${content_dir}/Files",
                    source: "${root_path}",
                    ifNotExists: true
                ),
                InstallStep(
                    action: .exec,
                    path: "${executable_path}",
                    arguments: [
                        "config", "init",
                        "--database", "${data_dir}/filebrowser.db",
                        "--root", "${content_dir}",
                        "--address", "0.0.0.0",
                        "--port", "${port}",
                        "--disableExec",
                    ]
                ),
                InstallStep(
                    action: .exec,
                    path: "${executable_path}",
                    arguments: [
                        "users", "add",
                        "${files_username}", "${files_password}",
                        "--database", "${data_dir}/filebrowser.db",
                        "--scope", ".",
                        "--perm.admin",
                    ]
                ),
            ])
        )

        return (capability, bundle, [runtimeUnit])
    }()
}
