import SwiftUI

struct SettingsView: View {
    @Environment(HavenSettingsModel.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("General") {
                LabeledContent("Data Directory") {
                    Text(settings.dataDirectory)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                Toggle("Automatically Start Installed Services", isOn: $settings.autoStartServices)
            }

            Section("Paths") {
                LabeledContent("Base Directory") {
                    Text(settings.baseDirectory)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Downloads") {
                    Text(settings.downloadsDirectory)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Installed Artifacts") {
                    Text(settings.artifactsDirectory)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Advanced") {
                Toggle("Show Internal Details", isOn: $settings.showInternalDetails)
                LabeledContent("Logs") {
                    Button("Open Logs Folder") {}
                }
                LabeledContent("Service State") {
                    Button("Rebuild Service State") {}
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text("\(settings.version) (\(settings.buildNumber))")
                        .foregroundStyle(.secondary)
                }
                Text("Haven is a local service manager for macOS. It installs and manages self-hosted services on your Mac.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SettingsView()
        .environment(HavenSettingsModel())
        .frame(width: 600, height: 500)
}
