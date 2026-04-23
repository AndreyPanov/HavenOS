import SwiftUI
import HavenFacade

/// Sign-in sheet for Navidrome-backed music.
struct MusicConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let facade: NavidromeMusicFacade

    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Sign in to your library")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Enter your Navidrome account credentials.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .disabled(isWorking)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .disabled(isWorking)
                    .onSubmit { signIn() }
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                    .controlSize(.large)

                Button("Sign In") { signIn() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(username.isEmpty || password.isEmpty || isWorking)
            }

            if isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .padding(32)
        .frame(width: 380)
    }

    private func signIn() {
        guard !username.isEmpty, !password.isEmpty else { return }
        isWorking = true
        errorMessage = nil

        Task {
            do {
                try await facade.connect(username: username, password: password)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
