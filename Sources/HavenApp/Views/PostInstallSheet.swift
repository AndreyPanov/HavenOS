import SwiftUI
import HavenCore

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

            // Content: structured onboarding or legacy text
            ScrollView {
                if let onboarding = info.onboarding, !onboarding.steps.isEmpty {
                    OnboardingStepsView(steps: onboarding.steps)
                } else if !info.instructions.isEmpty {
                    Text(info.instructions)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
        .frame(width: 520)
        .frame(minHeight: 360)
    }
}

#Preview("Structured Onboarding") {
    PostInstallSheet(info: PendingInstructions(
        serviceName: "Calibre-Web",
        instructions: "",
        onboarding: Onboarding(steps: [
            OnboardingStep(
                type: .credentials,
                title: "Default Credentials",
                body: "Log in with the default admin account. Change the password after first login.",
                fields: [
                    OnboardingField(label: "Username", value: "admin"),
                    OnboardingField(label: "Password", value: "admin123"),
                ]
            ),
            OnboardingStep(
                type: .action,
                title: "Open Calibre-Web",
                body: "Access your library in the browser.",
                url: "http://localhost:8083"
            ),
            OnboardingStep(
                type: .info,
                title: "Configure Library Path",
                body: "On first login, set the Calibre database location to: ~/.haven/Services/calibre-web/data"
            ),
        ])
    ))
}

#Preview("Legacy Instructions") {
    PostInstallSheet(info: PendingInstructions(
        serviceName: "Hello Service",
        instructions: "Your service is running at http://localhost:8080\n\nVisit the URL to verify it's working."
    ))
}
