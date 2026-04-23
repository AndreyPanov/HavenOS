import AppKit
import SwiftUI

/// "Listen on your devices" section — server address for Subsonic clients.
struct MusicDeviceAccessSection: View {
    let serverAddress: String

    @State private var copied = false
    @State private var showingQRPopover = false
    @State private var showingGuides = true

    var body: some View {
        GroupBox("Listen on your devices") {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use this address in a music app on your phone or tablet to stream your library.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server address")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)

                        HStack(spacing: 8) {
                            linkRow(value: serverAddress)

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
                            guideRow("iphone", "iPhone / iPad", "Amperfy or Substreamer → add server → paste address")
                            guideRow("phone", "Android", "Symfonium or DSub → add server → paste address")
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

    // MARK: - Link Row

    private func linkRow(value: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                copyToClipboard(value)
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

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}
