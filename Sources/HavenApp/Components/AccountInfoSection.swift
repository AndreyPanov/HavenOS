import SwiftUI

/// Shared "Signed in as" section used by capability home views.
struct AccountInfoSection: View {
    let username: String

    var body: some View {
        GroupBox {
            LabeledContent("Signed in as") {
                HStack(spacing: 8) {
                    Text(username)
                        .foregroundStyle(.secondary)
                    Text("Change in Settings")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
