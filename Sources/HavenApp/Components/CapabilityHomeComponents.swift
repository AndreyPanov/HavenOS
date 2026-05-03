import SwiftUI
import HavenFacade

enum CapabilityUIState: Equatable {
    case stopped
    case starting
    case needsSetup
    case settingUp
    case setupWizard(SetupPhase)
    case empty
    case ready
    case updating
    case error(String)
}

struct CenteredCapabilityCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}

struct CapabilityStatView: View {
    let count: Int
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(count)")
                .font(.system(.title, design: .rounded, weight: .semibold))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct LibraryFolderRow: View {
    let path: String
    let canRemove: Bool
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(path)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            if canRemove, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Remove this folder")
            }
        }
    }
}

@ViewBuilder
@MainActor
func centeredCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    CenteredCapabilityCard(content: content)
}

@MainActor
func statView(count: Int, label: String) -> some View {
    CapabilityStatView(count: count, label: label)
}
