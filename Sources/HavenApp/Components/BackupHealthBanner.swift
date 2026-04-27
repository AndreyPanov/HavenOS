import SwiftUI
import HavenBackup

/// Compact backup health banner for the Home view.
///
/// Shows warnings and failures only — hidden when backup is healthy or not configured.
/// Tapping navigates to the Backup tab.
struct BackupHealthBanner: View {
    let health: BackupHealth
    var onNavigateToBackup: (() -> Void)?

    var body: some View {
        switch health.status {
        case .notConfigured, .healthy:
            EmptyView()

        case .neverRun:
            bannerRow(
                icon: "clock.badge.questionmark",
                message: "Backup configured but hasn't run yet",
                color: .orange
            )

        case .overdue(let days):
            bannerRow(
                icon: "exclamationmark.triangle.fill",
                message: "Backup overdue by \(days) day\(days == 1 ? "" : "s")",
                color: .orange
            )

        case .warning(let message):
            bannerRow(
                icon: "exclamationmark.triangle.fill",
                message: message,
                color: .orange
            )

        case .failed(let message):
            bannerRow(
                icon: "xmark.circle.fill",
                message: message,
                color: .red
            )
        }
    }

    @ViewBuilder
    private func bannerRow(icon: String, message: String, color: Color) -> some View {
        Button {
            onNavigateToBackup?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.body)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text("View")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// Protection status overview showing a circular score and per-capability breakdown.
struct ProtectionStatusView: View {
    let health: BackupHealth

    var body: some View {
        VStack(spacing: 16) {
            // Circular protection score
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 6)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: CGFloat(health.protectionScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: health.protectionScore)

                VStack(spacing: 2) {
                    Text("\(health.protectionScore)%")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text("Protected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Per-capability rows
            if !health.capabilities.isEmpty {
                VStack(spacing: 8) {
                    ForEach(health.capabilities) { cap in
                        HStack(spacing: 8) {
                            Image(systemName: cap.isProtected ? "checkmark.circle.fill" : "circle.dashed")
                                .foregroundStyle(cap.isProtected ? .green : .secondary)
                                .font(.body)

                            Text(cap.displayName)
                                .font(.callout)

                            Spacer()

                            if let date = cap.lastBackedUp {
                                Text(date.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if cap.destinationPath != nil {
                                Text("Not backed up yet")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Not configured")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var scoreColor: Color {
        switch health.protectionScore {
        case 80...100: .green
        case 40..<80: .orange
        default: .red
        }
    }
}
