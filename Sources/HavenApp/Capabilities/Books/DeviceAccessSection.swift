import AppKit
import SwiftUI

/// "Read on Your Devices" section — OPDS-first, credential-free e-reader flow.
///
/// The primary use case: user adds books and wants to read them on an e-reader or tablet.
/// OPDS feed URL has the API key baked in, so no login is needed on the device.
struct DeviceAccessSection: View {
    let serverAddress: String
    let opdsURL: String?

    @State private var copiedField: String?
    @State private var showingQRPopover = false

    var body: some View {
        GroupBox("Read on Your Devices") {
            VStack(spacing: 0) {
                if let opds = opdsURL {
                    // Primary: OPDS feed (credential-free)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Open your e-reader app, go to **Add OPDS catalog**, and paste this address:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            addressRow(value: opds, fieldID: "opds")

                            Button {
                                showingQRPopover = true
                            } label: {
                                Image(systemName: "qrcode")
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .popover(isPresented: $showingQRPopover, arrowEdge: .bottom) {
                                qrPopoverContent(opds: opds)
                            }
                        }
                    }

                    Divider().padding(.vertical, 10)

                    // App guides
                    readerGuides
                } else {
                    HStack {
                        Text("Device access will be available once the library is fully set up.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Address Row

    private func addressRow(value: String, fieldID: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                copyToClipboard(value, fieldID: fieldID)
            } label: {
                Image(systemName: copiedField == fieldID ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copiedField == fieldID ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Reader Guides

    private var readerGuides: some View {
        VStack(spacing: 0) {
            DisclosureGroup("Books & E-Readers") {
                VStack(spacing: 1) {
                    guideRow(
                        icon: "book.closed",
                        device: "Kobo / Kindle",
                        app: "KOReader",
                        hint: "Install KOReader → OPDS catalog → add feed"
                    )
                    guideRow(
                        icon: "ipad.and.iphone",
                        device: "iPhone / iPad",
                        app: "Panels or KyBook 3",
                        hint: "Add OPDS feed in app settings"
                    )
                    guideRow(
                        icon: "phone",
                        device: "Android",
                        app: "Moon+ Reader or Librera",
                        hint: "Add OPDS catalog → paste feed URL"
                    )
                }
                .padding(.top, 6)
            }
            .font(.callout)

            Divider().padding(.vertical, 6)

            DisclosureGroup("Comics & Manga") {
                VStack(spacing: 1) {
                    guideRow(
                        icon: "ipad.and.iphone",
                        device: "iPhone / iPad",
                        app: "Panels or Chunky",
                        hint: "Add OPDS feed in app settings"
                    )
                    guideRow(
                        icon: "phone",
                        device: "Android",
                        app: "Mihon",
                        hint: "Install Kavita extension → add server URL"
                    )
                }
                .padding(.top, 6)
            }
            .font(.callout)
        }
    }

    private func guideRow(icon: String, device: String, app: String, hint: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text(device)
                        .fontWeight(.medium)
                        .font(.caption)
                    Text("  ·  ")
                        .foregroundStyle(.quaternary)
                        .font(.caption)
                    Text(app)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - QR Popover

    private func qrPopoverContent(opds: String) -> some View {
        VStack(spacing: 16) {
            Text("Scan with your device")
                .font(.headline)

            QRCodeView(content: opds, size: 160)

            Text("Point your device's camera at the code,\nor scan from your e-reader app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
    }

    // MARK: - Clipboard

    private func copyToClipboard(_ string: String, fieldID: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        copiedField = fieldID
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedField == fieldID {
                copiedField = nil
            }
        }
    }
}
