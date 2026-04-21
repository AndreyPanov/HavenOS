import SwiftUI
import HavenFacade

/// API key entry sheet for the mock books backend.
/// This is MockBooksFacade-specific — takes the concrete type, not the protocol.
struct MockBooksSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let facade: MockBooksFacade

    @State private var apiKey = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "key")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Connect to your library")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Enter your API key to access the library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Form
            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { connect() }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                Button("Connect") {
                    connect()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(apiKey.isEmpty)
            }
        }
        .padding(32)
        .frame(width: 360)
    }

    private func connect() {
        guard !apiKey.isEmpty else { return }
        errorMessage = nil
        do {
            try facade.connect(apiKey: apiKey)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
