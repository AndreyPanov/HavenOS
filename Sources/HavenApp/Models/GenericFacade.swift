import Foundation
import HavenFacade

/// Default facade for capabilities without a custom adapter.
///
/// Provides standard lifecycle actions (start/stop/restart/open/remove)
/// by delegating to ServiceManager. State is derived from InstalledService.
@MainActor
@Observable
final class GenericFacade: CapabilityFacade {
    let capabilityID: String
    private(set) var state: CapabilityState = .idle
    private(set) var health: CapabilityHealth = .unknown
    private(set) var advancedURL: URL?

    private let lifecycle: FacadeLifecycle

    init(capabilityID: String, serviceManager: ServiceManager) {
        self.capabilityID = capabilityID
        self.lifecycle = FacadeLifecycle(serviceManager: serviceManager)
        refresh()
    }

    var availableActions: [CapabilityAction] {
        switch state {
        case .ready, .degraded:
            var actions: [CapabilityAction] = [.stop, .restart]
            if advancedURL != nil {
                actions.insert(.openInBrowser, at: 0)
            }
            actions.append(.remove)
            return actions
        case .idle, .error:
            return [.start, .remove]
        case .starting:
            return []
        }
    }

    func perform(_ action: CapabilityAction) async throws {
        let handled = try await lifecycle.perform(action, capabilityID: capabilityID)
        if !handled {
            throw FacadeError.actionNotAvailable(action.id)
        }
    }

    func refresh() {
        let result = lifecycle.refreshState(for: capabilityID)
        state = result.state
        health = result.health
        advancedURL = result.advancedURL
    }
}
