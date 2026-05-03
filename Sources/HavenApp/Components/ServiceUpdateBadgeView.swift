import SwiftUI
import HavenInstaller

struct ServiceUpdateBadgeView: View {
    let state: ServiceUpdateState

    private var presentation: ServiceUpdatePresentation {
        ServiceUpdatePresentation.make(for: state)
    }

    var body: some View {
        HStack(spacing: 5) {
            if presentation.showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: presentation.systemImage)
                    .font(.caption2)
            }
            Text(presentation.title)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private var color: Color {
        switch presentation.tone {
        case .neutral:
            .secondary
        case .available:
            .blue
        case .progress:
            .accentColor
        case .success:
            .green
        case .warning:
            .orange
        case .failure:
            .red
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ServiceUpdateBadgeView(state: .checking)
        ServiceUpdateBadgeView(state: .updateAvailable(UpdateCandidate(
            unitID: "unit",
            repo: "owner/repo",
            currentVersion: "v1.0.0",
            latestVersion: "v1.1.0"
        )))
        ServiceUpdateBadgeView(state: .rolledBack(reason: "Healthcheck failed"))
    }
    .padding()
}
