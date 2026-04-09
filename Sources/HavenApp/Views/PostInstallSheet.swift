import SwiftUI

struct PostInstallSheet: View {
    let info: PendingInstructions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(info.serviceName) Installed")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Getting started")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Instructions
            ScrollView {
                Text(info.instructions)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Dismiss
            HStack {
                Spacer()
                Button("Got it") {
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 480)
        .frame(minHeight: 300)
    }
}

#Preview {
    PostInstallSheet(info: PendingInstructions(
        serviceName: "Calibre-Web",
        instructions: "Log in with default credentials:\n  Username: admin\n  Password: admin123\n\nDatabase Setup: If you do not have a Calibre database, download a sample from:\nhttps://github.com/janeczku/calibre-web/raw/master/library/metadata.db"
    ))
}
