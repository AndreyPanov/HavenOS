import Foundation
import HavenFacade

/// Shared lifecycle helpers for facade implementations.
///
/// Eliminates duplicated ServiceManager delegation across
/// GenericFacade, KavitaBooksFacade, and other facades.
@MainActor
struct FacadeLifecycle {
    weak var serviceManager: ServiceManager?

    /// Perform a standard lifecycle action (start/stop/restart/remove).
    /// Returns true if the action was handled, false if not recognized.
    func perform(_ action: CapabilityAction, capabilityID: String) async throws -> Bool {
        guard let sm = serviceManager else { return false }

        switch action.id {
        case CapabilityAction.start.id:
            await sm.startService(capabilityID: capabilityID)
            return true
        case CapabilityAction.stop.id:
            await sm.stopService(capabilityID: capabilityID)
            return true
        case CapabilityAction.restart.id:
            await sm.stopService(capabilityID: capabilityID)
            await sm.startService(capabilityID: capabilityID)
            return true
        case CapabilityAction.remove.id:
            await sm.uninstallService(capabilityID: capabilityID)
            return true
        default:
            return false
        }
    }

    /// Map InstalledService status to CapabilityState + CapabilityHealth.
    func refreshState(for capabilityID: String) -> (
        state: CapabilityState,
        health: CapabilityHealth,
        advancedURL: URL?,
        service: InstalledService?
    ) {
        guard let sm = serviceManager,
              let service = sm.installedServices.first(where: { $0.id == capabilityID }) else {
            return (.idle, .unknown, nil, nil)
        }

        let state: CapabilityState
        let health: CapabilityHealth

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

        let advancedURL = service.port.flatMap { URL(string: "http://localhost:\($0)") }

        return (state, health, advancedURL, service)
    }
}
