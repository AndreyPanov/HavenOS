import SwiftUI
import HavenFacade

/// Credential entry sheet for connecting Haven to Kavita.
struct BooksConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let facade: KavitaBooksFacade

    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Connect to your library")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Enter the account you created in Kavita.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Form
            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .disabled(isConnecting)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .disabled(isConnecting)
                    .onSubmit { connect() }
            }

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
                .disabled(username.isEmpty || password.isEmpty || isConnecting)
            }

            if isConnecting {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(32)
        .frame(width: 360)
    }

    private func connect() {
        guard !username.isEmpty, !password.isEmpty else { return }
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                try await facade.connect(username: username, password: password)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
}
