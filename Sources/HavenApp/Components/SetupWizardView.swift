import AppKit
import SwiftUI
import HavenFacade

/// Shared setup wizard used by all capability HomeViews.
///
/// Shows progressive inline cards for each setup step:
/// Server ready → Account choice → Account created → Choose folder → Scanning
struct SetupWizardView: View {
    let phase: SetupPhase
    let contentLabel: String
    let icon: String
    let facade: any ConnectableFacade
    var onChooseManaged: () -> Void
    var onChooseCustom: () -> Void
    var onPickFolder: () -> Void
    var onConfirmFolder: (String) -> Void
    var showFolderStep: Bool = true

    @State private var selectedPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setting up your \(contentLabel.lowercased()) library")
                .font(.headline)
            Text("Haven is configuring everything for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                // Step 1: Server ready
                stepCard(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    title: "Server ready",
                    completed: phase != .waitingForServer
                ) {
                    if phase == .waitingForServer {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for server to start\u{2026}")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Step 2: Account choice
                if phase != .waitingForServer {
                    stepCard(
                        icon: phase == .awaitingAccountChoice ? "person.crop.circle.badge.questionmark" : "checkmark.circle.fill",
                        iconColor: phase == .awaitingAccountChoice ? .blue : .green,
                        title: "Account",
                        completed: phase != .awaitingAccountChoice && phase != .creatingAccount
                    ) {
                        if phase == .awaitingAccountChoice {
                            accountChoiceContent
                        } else if phase == .creatingAccount {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Creating your account\u{2026}")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let username = facade.connectedUsername {
                            Text("Signed in as \(username)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Step 3: Choose folder
                if showFolderStep && (phase == .awaitingLibraryPath || phase == .creatingLibrary || isScanning(phase)) {
                    stepCard(
                        icon: phase == .awaitingLibraryPath ? "folder.badge.questionmark" : "checkmark.circle.fill",
                        iconColor: phase == .awaitingLibraryPath ? .blue : .green,
                        title: "Where is your \(contentLabel.lowercased())?",
                        completed: phase != .awaitingLibraryPath
                    ) {
                        if phase == .awaitingLibraryPath {
                            folderPickerContent
                        } else if !selectedPath.isEmpty {
                            Text(selectedPath)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Step 4: Scanning
                if isScanning(phase) || phase == .creatingLibrary {
                    stepCard(
                        icon: "magnifyingglass",
                        iconColor: .blue,
                        title: "Scanning your library\u{2026}",
                        completed: false
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            if case .scanning(let progress) = phase, let pct = progress {
                                ProgressView(value: pct / 100)
                                Text("\(Int(pct))% complete")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("This may take a while for large libraries.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: phaseKey(phase))
        }
    }

    // MARK: - Account Choice

    private var accountChoiceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How do you want to sign in?")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Set it up for me") {
                    onChooseManaged()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.regular)

                Button("I have my own account") {
                    onChooseCustom()
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
            }

            Text("\"Set it up for me\" creates a Haven-managed account. You can switch to your own account later.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Folder Picker

    private var folderPickerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose the folder where your \(contentLabel.lowercased()) files are stored.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(selectedPath.isEmpty ? "No folder selected" : selectedPath)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(selectedPath.isEmpty ? .tertiary : .primary)

                Button("Choose\u{2026}") {
                    pickFolder()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            Button("Continue") {
                onConfirmFolder(selectedPath)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.regular)
            .disabled(selectedPath.isEmpty)

            Text("You can add more folders later.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose your \(contentLabel.lowercased()) folder"

        if !selectedPath.isEmpty {
            let expanded = (selectedPath as NSString).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expanded)
        }

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }

    // MARK: - Step Card

    private func stepCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        completed: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(completed ? .green : iconColor)
                    .frame(width: 24, alignment: .center)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(completed ? .secondary : .primary)
                    content()
                }
            }
            .padding(4)
        }
    }

    // MARK: - Helpers

    private func isScanning(_ phase: SetupPhase) -> Bool {
        if case .scanning = phase { return true }
        return false
    }

    private func phaseKey(_ phase: SetupPhase) -> String {
        switch phase {
        case .waitingForServer: "waiting"
        case .awaitingAccountChoice: "accountChoice"
        case .creatingAccount: "creating"
        case .awaitingLibraryPath: "path"
        case .awaitingLibraryType: "type"
        case .creatingLibrary: "library"
        case .scanning: "scanning"
        case .complete: "complete"
        }
    }
}
