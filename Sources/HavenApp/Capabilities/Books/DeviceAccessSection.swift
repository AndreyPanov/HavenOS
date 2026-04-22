import AppKit
import SwiftUI

/// "Read on Other Devices" section showing server address, OPDS feed, and QR codes.
struct DeviceAccessSection: View {
    let serverAddress: String
    let opdsURL: String?

    @State private var copiedField: String?
    @State private var showingQRPopover = false

    var body: some View {
        GroupBox("Read on Other Devices") {
            VStack(spacing: 0) {
                addressRow(
                    label: "Web address",
                    value: serverAddress,
                    fieldID: "web"
                )

                if let opds = opdsURL {
                    Divider().padding(.vertical, 6)
                    addressRow(
                        label: "Reader app feed",
                        value: opds,
                        fieldID: "opds"
                    )
                }

                Divider().padding(.vertical, 6)

                HStack {
                    Text("Use these addresses on phones, tablets, or e-readers on your network.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Show QR Code") {
                        showingQRPopover = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .popover(isPresented: $showingQRPopover, arrowEdge: .bottom) {
                        qrPopoverContent
                    }
                }
            }
            .padding(4)
        }
    }

    // MARK: - Address Row

    private func addressRow(label: String, value: String, fieldID: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
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
        .font(.callout)
    }

    // MARK: - QR Popover

    private var qrPopoverContent: some View {
        VStack(spacing: 16) {
            Text("Scan to connect")
                .font(.headline)

            HStack(spacing: 24) {
                VStack(spacing: 8) {
                    QRCodeView(content: serverAddress, size: 140)
                    Text("Web")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let opds = opdsURL {
                    VStack(spacing: 8) {
                        QRCodeView(content: opds, size: 140)
                        Text("OPDS Feed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("Point your device's camera or reader app at the QR code.")
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
