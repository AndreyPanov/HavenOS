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

    private weak var serviceManager: ServiceManager?

    init(capabilityID: String, serviceManager: ServiceManager) {
        self.capabilityID = capabilityID
        self.serviceManager = serviceManager
        refresh()
    }

    var availableActions: [CapabilityAction] {
        switch state {
        case .ready:
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
        case .degraded:
            var actions: [CapabilityAction] = [.stop, .restart]
            if advancedURL != nil {
                actions.insert(.openInBrowser, at: 0)
            }
            actions.append(.remove)
            return actions
        }
    }

    func perform(_ action: CapabilityAction) async throws {
        guard let sm = serviceManager else { return }

        switch action.id {
        case CapabilityAction.start.id:
            await sm.startService(capabilityID: capabilityID)
        case CapabilityAction.stop.id:
            await sm.stopService(capabilityID: capabilityID)
        case CapabilityAction.restart.id:
            await sm.stopService(capabilityID: capabilityID)
            await sm.startService(capabilityID: capabilityID)
        case CapabilityAction.remove.id:
            await sm.uninstallService(capabilityID: capabilityID)
        default:
            throw FacadeError.actionNotAvailable(action.id)
        }
    }

    func refresh() {
        guard let sm = serviceManager else { return }
        guard let service = sm.installedServices.first(where: { $0.id == capabilityID }) else {
            state = .idle
            health = .unknown
            advancedURL = nil
            return
        }

        switch service.status {
        case .running:
            state = .ready
            health = .healthy
        case .stopped:
            state = .idle
            health = .unknown
        case .failed:
            state = .error("Service failed")
            health = CapabilityHealth(status: .unhealthy, message: "Service failed")
        case .installing:
            state = .starting
            health = .unknown
        }

        if let urlString = service.localURL, let url = URL(string: urlString) {
            advancedURL = url
        } else {
            advancedURL = nil
        }
    }
}
