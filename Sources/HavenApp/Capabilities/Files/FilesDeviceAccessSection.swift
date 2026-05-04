import AppKit
import SwiftUI

struct FilesDeviceAccessSection: View {
    let serverAddress: String
    let username: String?
    let password: String?

    @State private var copiedField: CopiedField?
    @State private var showingQRPopover = false
    @State private var showPassword = false

    private enum CopiedField {
        case address
        case username
        case password
    }

    var body: some View {
        GroupBox("Open on other devices") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Address")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                        fieldRow(value: serverAddress, copied: copiedField == .address) {
                            copyToClipboard(serverAddress, field: .address)
                        }
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
                        qrPopoverContent
                    }
                }

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
            }
            .padding(4)
        }
    }

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

    private var qrPopoverContent: some View {
        VStack(spacing: 16) {
            Text("Scan with your device")
                .font(.headline)
            QRCodeView(content: serverAddress, size: 160)
            Text(serverAddress)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(20)
    }

    private func copyToClipboard(_ string: String, field: CopiedField) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        copiedField = field
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedField == field {
                copiedField = nil
            }
        }
    }
}
