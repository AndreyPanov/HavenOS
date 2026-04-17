import AppKit
import SwiftUI
import HavenCore

/// Reusable view that renders a list of onboarding steps.
///
/// Used in both `PostInstallSheet` (after install) and `ServiceDetailView`
/// (re-viewable setup guide).
struct OnboardingStepsView: View {
    let steps: [OnboardingStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                OnboardingStepRow(step: step, index: index + 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingStepRow: View {
    let step: OnboardingStep
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Step header with number badge and icon
            HStack(spacing: 8) {
                Text("\(index)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(iconColor, in: Circle())

                Image(systemName: iconName)
                    .foregroundStyle(iconColor)

                Text(step.title)
                    .font(.headline)
            }

            // Body text
            Text(step.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            // Credential / info fields
            if !step.fields.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(step.fields.enumerated()), id: \.offset) { _, field in
                        HStack {
                            Text(field.label)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(field.value)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
            }

            // Action URL button
            if let urlString = step.url, let url = URL(string: urlString) {
                Button("Open in Browser", systemImage: "globe") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
    }

    private var iconName: String {
        switch step.type {
        case .info: "info.circle.fill"
        case .credentials: "key.fill"
        case .action: "cursorarrow.click.2"
        }
    }

    private var iconColor: Color {
        switch step.type {
        case .info: .blue
        case .credentials: .orange
        case .action: .green
        }
    }
}
