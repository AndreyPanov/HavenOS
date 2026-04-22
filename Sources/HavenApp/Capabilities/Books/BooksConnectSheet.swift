import SwiftUI
import HavenFacade

/// Library setup sheet for Kavita-backed books.
/// User chooses: create a new account (first run) or sign in (returning).
struct BooksConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let facade: KavitaBooksFacade

    @State private var mode: Mode = .choose
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private enum Mode: Equatable {
        case choose
        case createAccount
        case signIn
    }

    var body: some View {
        VStack(spacing: 24) {
            switch mode {
            case .choose:
                chooseView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .createAccount:
                accountFormView(
                    icon: "person.crop.circle.badge.plus",
                    title: "Create your account",
                    subtitle: "Choose a username and password for your book library.",
                    actionLabel: "Create Account",
                    action: createAccount
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            case .signIn:
                accountFormView(
                    icon: "person.crop.circle",
                    title: "Sign in to your library",
                    subtitle: "Enter your existing account credentials.",
                    actionLabel: "Sign In",
                    action: signIn
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .padding(32)
        .frame(width: 380)
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: mode)
    }

    // MARK: - Choose Mode

    private var chooseView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Set up your library")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Is this your first time using this library?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button {
                    mode = .createAccount
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create Account")
                                .fontWeight(.medium)
                            Text("I'm setting this up for the first time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                Button {
                    mode = .signIn
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign In")
                                .fontWeight(.medium)
                            Text("I already have an account")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Account Form (Shared)

    private func accountFormView(
        icon: String,
        title: String,
        subtitle: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(subtitle)
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
                    .textContentType(mode == .createAccount ? .newPassword : .password)
                    .disabled(isWorking)
                    .onSubmit { action() }

                if mode == .createAccount {
                    Text("Password must be 6+ characters with uppercase, lowercase, number, and special character.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Back") {
                    errorMessage = nil
                    mode = .choose
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                Button(actionLabel) { action() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(username.isEmpty || password.isEmpty || isWorking)
            }

            if isWorking {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - Actions

    private func createAccount() {
        guard !username.isEmpty, !password.isEmpty else { return }
        isWorking = true
        errorMessage = nil

        Task {
            do {
                try await facade.createAccount(username: username, password: password)
                dismiss()
            } catch {
                // If registration is blocked, guide user to sign in instead
                let msg = error.localizedDescription
                if msg.lowercased().contains("not allowed") || msg.lowercased().contains("already") {
                    errorMessage = "An admin account already exists. Use Sign In instead."
                } else {
                    errorMessage = msg
                }
            }
            isWorking = false
        }
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
