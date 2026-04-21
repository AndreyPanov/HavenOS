import AppKit
import SwiftUI
import HavenFacade

/// Renders action buttons from a facade's available actions.
struct FacadeActionBar: View {
    let facade: any CapabilityFacade
    let isPerformingAction: Bool

    var body: some View {
        HStack(spacing: 12) {
            ForEach(facade.availableActions.filter { $0.role != .destructive }) { action in
                actionButton(for: action)
            }

            Spacer()

            ForEach(facade.availableActions.filter { $0.role == .destructive }) { action in
                actionButton(for: action)
            }
        }
    }

    @ViewBuilder
    private func actionButton(for action: CapabilityAction) -> some View {
        if action.id == CapabilityAction.openInBrowser.id, let url = facade.advancedURL {
            Button(action.label, systemImage: action.systemImage) {
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        } else if action.role == .primary {
            Button(action.label, systemImage: action.systemImage) {
                Task { try? await facade.perform(action) }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isPerformingAction)
        } else {
            Button(action.label, systemImage: action.systemImage, role: action.role == .destructive ? .destructive : nil) {
                Task { try? await facade.perform(action) }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(isPerformingAction)
        }
    }
}
