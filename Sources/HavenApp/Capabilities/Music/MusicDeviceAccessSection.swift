import AppKit
import SwiftUI

/// "Listen on your devices" section — server address + credentials for Subsonic clients.
struct MusicDeviceAccessSection: View {
    let serverAddress: String
    let localAddress: String?
    let username: String?
    let password: String?

    @State private var copiedField: CopiedField?
    @State private var showingQRPopover = false
    @State private var showingGuides = true
    @State private var showPassword = false

    private enum CopiedField { case address, username, password }

    var body: some View {
        GroupBox("Listen on your devices") {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Subsonic-compatible music apps require a server address, username, and password. Copy each field below into your player's settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Server address
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server address")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)

                        HStack(spacing: 8) {
                            fieldRow(value: serverAddress, copied: copiedField == .address) {
                                copyToClipboard(serverAddress, field: .address)
                            }

                            Button {
                                showingQRPopover = true
                            } label: {
                                Image(systemName: "qrcode")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .help("Show QR Code")
                            .popover(isPresented: $showingQRPopover, arrowEdge: .bottom) {
                                qrPopoverContent(link: serverAddress)
                            }
                        }
                    }

                    // Credentials
                    if let username, let password {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Username")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .textCase(.uppercase)

                                fieldRow(value: username, copied: copiedField == .username) {
                                    copyToClipboard(username, field: .username)
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Password")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .textCase(.uppercase)

                                HStack(spacing: 8) {
                                    fieldRow(
                                        value: showPassword ? password : String(repeating: "•", count: 8),
                                        copied: copiedField == .password
                                    ) {
                                        copyToClipboard(password, field: .password)
                                    }

                                    Button {
                                        showPassword.toggle()
                                    } label: {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                    .help(showPassword ? "Hide password" : "Show password")
                                }
                            }
                        }
                    }

                    DeviceCredentialActionsView(
                        serverAddress: serverAddress,
                        localAddress: localAddress,
                        username: username,
                        password: password,
                        tokenURL: nil
                    )
                }

                // Player guides
                VStack(alignment: .leading, spacing: 0) {
                    Divider().padding(.vertical, 12)

                    Button {
                        withAnimation { showingGuides.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .rotationEffect(.degrees(showingGuides ? 90 : 0))
                            Text("How to connect your player")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if showingGuides {
                        VStack(alignment: .leading, spacing: 6) {
                            guideRow("iphone", "iPhone / iPad", "Amperfy or Substreamer → add server → paste address + credentials")
                            guideRow("phone", "Android", "Symfonium or DSub → add server → paste address + credentials")
                            guideRow("desktopcomputer", "Desktop", "Open in browser or use Sonixd")
                        }
                        .padding(.top, 8)
                        .padding(.leading, 10)
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Field Row

    private func fieldRow(value: String, copied: Bool, onCopy: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                onCopy()
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Guide Row

    private func guideRow(_ icon: String, _ device: String, _ steps: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(device)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(steps)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - QR Popover

    private func qrPopoverContent(link: String) -> some View {
        VStack(spacing: 16) {
            Text("Scan with your device")
                .font(.headline)

            QRCodeView(content: link, size: 160)

            Text("Point your device's camera at the code,\nor enter the address in your music app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }

    // MARK: - Clipboard

    private func copyToClipboard(_ string: String, field: CopiedField) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        copiedField = field
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedField == field { copiedField = nil }
        }
    }
}
