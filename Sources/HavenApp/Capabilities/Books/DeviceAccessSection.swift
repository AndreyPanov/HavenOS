import AppKit
import SwiftUI

/// "Read on other devices" section — credential-free e-reader access.
///
/// Shows a single access link (with API key baked in) that users
/// paste into their e-reader app. No login needed on the device.
struct DeviceAccessSection: View {
    let serverAddress: String
    let opdsURL: String?

    @State private var copied = false
    @State private var showingQRPopover = false
    @State private var showingGuides = true

    var body: some View {
        GroupBox("Read on your devices") {
            VStack(alignment: .leading, spacing: 0) {
                if let opds = opdsURL {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Use this link on your phone, tablet, or e-reader to access your books.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // Labeled link
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Library address")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)

                            HStack(spacing: 8) {
                                linkRow(value: opds)

                                Button {
                                    showingQRPopover = true
                                } label: {
                                    Image(systemName: "qrcode")
                                }
                                .buttonStyle(.glass)
                                .controlSize(.small)
                                .help("Show QR Code")
                                .popover(isPresented: $showingQRPopover, arrowEdge: .bottom) {
                                    qrPopoverContent(link: opds)
                                }
                            }
                        }
                    }

                    // Reader guides
                    VStack(alignment: .leading, spacing: 0) {
                        Divider().padding(.vertical, 12)

                        Button {
                            withAnimation { showingGuides.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .rotationEffect(.degrees(showingGuides ? 90 : 0))
                                Text("How to connect your reader")
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        if showingGuides {
                            VStack(alignment: .leading, spacing: 6) {
                                guideRow("book.closed", "Kobo / Kindle", "KOReader → add catalog → paste link")
                                guideRow("ipad.and.iphone", "iPhone / iPad", "Panels or KyBook → add catalog → paste link")
                                guideRow("phone", "Android", "Moon+ Reader or Librera → add catalog → paste link")
                                guideRow("text.book.closed", "Comics & Manga", "Panels, Chunky, or Mihon → add server → paste link")
                            }
                            .padding(.top, 8)
                            .padding(.leading, 10)
                        }
                    }
                } else {
                    Text("Device access will be available once your library is ready.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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

    // MARK: - Reader Guide Row

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

            Text("Point your device's camera at the code,\nor scan from your e-reader app.")
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
