import AppKit
import SwiftUI

struct DeviceCredentialActionsView: View {
    let serverAddress: String
    let localAddress: String?
    let username: String?
    let password: String?
    let tokenURL: String?

    @State private var copiedAll = false
    @State private var showingPasswordsGuide = false

    var body: some View {
        HStack(spacing: 8) {
            Button(copiedAll ? "Copied" : "Copy All", systemImage: copiedAll ? "checkmark" : "doc.on.doc") {
                copyAll()
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            Button("Open", systemImage: "globe") {
                openURL(tokenURL ?? serverAddress)
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            Button("Passwords", systemImage: "key") {
                showingPasswordsGuide = true
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Open Passwords to save these details manually")
            .popover(isPresented: $showingPasswordsGuide, arrowEdge: .bottom) {
                passwordsGuide
            }
        }
    }

    private var passwordsGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Save in Passwords")
                    .font(.headline)

                Text(passwordsGuideMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                guideRow("doc.on.doc", "Copy the Haven details.")
                guideRow("plus.circle", "In Passwords, add a new password.")
                guideRow("network", "Use the LAN address as the website.")
                if username != nil || password != nil {
                    guideRow("person.text.rectangle", "Paste the username and password.")
                } else {
                    guideRow("link", "Paste the access link as the website or note.")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Website")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Text(tokenURL ?? serverAddress)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                Button(copiedAll ? "Copied" : "Copy All", systemImage: copiedAll ? "checkmark" : "doc.on.doc") {
                    copyAll()
                }
                .controlSize(.small)

                Button("Open Passwords", systemImage: "key") {
                    openPasswords()
                    showingPasswordsGuide = false
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var passwordsGuideMessage: String {
        if username != nil || password != nil {
            return "Haven cannot insert local service credentials into Apple Passwords automatically. Copy these fields, then save them as a new Passwords item."
        }
        return "This Haven access link already contains what the device needs. Passwords can store it manually, but Haven cannot insert it automatically."
    }

    private func guideRow(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyAll() {
        var lines = ["LAN Address: \(serverAddress)"]
        if let localAddress {
            lines.append("Local Address: \(localAddress)")
        }
        if let tokenURL {
            lines.append("Link: \(tokenURL)")
        }
        if let username {
            lines.append("Username: \(username)")
        }
        if let password {
            lines.append("Password: \(password)")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        copiedAll = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedAll = false
        }
    }

    private func openURL(_ rawValue: String) {
        guard let url = URL(string: rawValue) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openPasswords() {
        let passwordsURL = URL(fileURLWithPath: "/System/Applications/Passwords.app")
        if FileManager.default.fileExists(atPath: passwordsURL.path) {
            NSWorkspace.shared.openApplication(
                at: passwordsURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return
        }

        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension") {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}
