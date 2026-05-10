import SwiftUI

struct AboutView: View {
    @Environment(HavenSettingsModel.self) private var settings
    @Environment(AppUpdateModel.self) private var appUpdateModel

    var body: some View {
        Form {
            Section("HavenOS") {
                LabeledContent("Version") {
                    Text("\(settings.version) (\(settings.buildNumber))")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("License") {
                    Text("MIT License")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Updates") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Button {
                            appUpdateModel.checkForUpdates()
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.down.circle")
                        }
                        .disabled(!appUpdateModel.canCheckForUpdates)

                        if let message = appUpdateModel.configurationMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Text("HavenOS is a local service manager for macOS. It installs and manages self-hosted services on your Mac.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            Section("Terms and Conditions") {
                LegalNote(
                    title: "Use",
                    text: "By downloading or using HavenOS, you agree to use it lawfully and only with services, media, and files that you are allowed to run, store, or access."
                )
                LegalNote(
                    title: "Local services",
                    text: "HavenOS installs and manages third-party open-source services on your Mac. Those services remain governed by their own licenses, documentation, and upstream terms."
                )
                LegalNote(
                    title: "Data and backups",
                    text: "You are responsible for your own content, service accounts, network exposure, and backups. Review settings before exposing any service outside your private network."
                )
                LegalNote(
                    title: "No warranty",
                    text: "HavenOS is provided as-is, without warranties or guarantees, to the fullest extent permitted by applicable law."
                )
            }

            Section("License") {
                Text("HavenOS is released under the MIT License. Open-source libraries and managed services listed below remain licensed by their respective authors.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Contact") {
                LabeledContent("Developer") {
                    Text("com///place")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Email") {
                    Link("atlas-stoker.4s@icloud.com", destination: legalContactEmailURL)
                }

                Text("Use this contact for support, legal notices, license questions, and EU user enquiries.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            Section("Open Source Libraries and Services") {
                ForEach(openSourceNotices) { notice in
                    OpenSourceNoticeRow(notice: notice)
                }

                Text("Each project is governed by its own license and upstream terms. Haven uses or manages these projects to provide updates, CLI parsing, books, music, movies, files, and media transcoding.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }
}

private struct LegalNote: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct OpenSourceNotice: Identifiable {
    let name: String
    let version: String
    let license: String
    let role: String
    let url: URL

    var id: String { name }
}

private struct OpenSourceNoticeRow: View {
    let notice: OpenSourceNotice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(notice.name)
                        .font(.headline)
                    Text(notice.version)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(notice.role)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(notice.license)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            Link(destination: notice.url) {
                Image(systemName: "arrow.up.right.square")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .help("Open upstream project")
        }
        .padding(.vertical, 4)
    }
}

private let legalContactEmailURL = URL(string: "mailto:atlas-stoker.4s@icloud.com")!

private let openSourceNotices: [OpenSourceNotice] = [
    OpenSourceNotice(
        name: "Sparkle",
        version: "2.9.1",
        license: "MIT License",
        role: "Software update framework for Haven.",
        url: URL(string: "https://github.com/sparkle-project/Sparkle")!
    ),
    OpenSourceNotice(
        name: "Swift Argument Parser",
        version: "1.7.1",
        license: "Apache License 2.0",
        role: "Command-line parsing for havenctl.",
        url: URL(string: "https://github.com/apple/swift-argument-parser")!
    ),
    OpenSourceNotice(
        name: "Kavita",
        version: "0.8.9.1",
        license: "GNU GPL v3",
        role: "Managed books, comics, and manga service.",
        url: URL(string: "https://github.com/Kareadita/Kavita")!
    ),
    OpenSourceNotice(
        name: "Navidrome",
        version: "0.61.2",
        license: "GNU GPL v3",
        role: "Managed music streaming service.",
        url: URL(string: "https://github.com/navidrome/navidrome")!
    ),
    OpenSourceNotice(
        name: "Jellyfin",
        version: "10.10.7",
        license: "GNU GPL v2",
        role: "Managed movies and TV streaming service.",
        url: URL(string: "https://github.com/jellyfin/jellyfin")!
    ),
    OpenSourceNotice(
        name: "Jellyfin FFmpeg / FFmpeg",
        version: "7.1.3-5",
        license: "LGPL/GPL (Jellyfin GPL build)",
        role: "Media playback and transcoding helper for Jellyfin.",
        url: URL(string: "https://github.com/jellyfin/jellyfin-ffmpeg")!
    ),
    OpenSourceNotice(
        name: "File Browser",
        version: "2.63.2",
        license: "Apache License 2.0",
        role: "Managed browser-based file access service.",
        url: URL(string: "https://github.com/filebrowser/filebrowser")!
    ),
]

#Preview {
    AboutView()
        .environment(HavenSettingsModel())
        .environment(AppUpdateModel())
        .frame(width: 700, height: 640)
}
