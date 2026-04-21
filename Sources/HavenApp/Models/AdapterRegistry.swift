import HavenFacade

/// Maps capability IDs to custom facade factories.
///
/// Capabilities without a registered factory get a ``GenericFacade``.
/// Register custom adapters for capabilities that need native UI
/// (e.g. Books/Kavita, Files/FileBrowser).
@MainActor
final class AdapterRegistry {
    typealias FacadeFactory = @MainActor (String, ServiceManager) -> any CapabilityFacade

    private var factories: [String: FacadeFactory] = [:]

    /// Register a custom facade factory for a capability ID.
    func register(capabilityID: String, factory: @escaping FacadeFactory) {
        factories[capabilityID] = factory
    }

    /// Create a facade for the given capability. Returns a custom facade if
    /// registered, otherwise a ``GenericFacade``.
    func createFacade(capabilityID: String, serviceManager: ServiceManager) -> any CapabilityFacade {
        if let factory = factories[capabilityID] {
            return factory(capabilityID, serviceManager)
        }
        return GenericFacade(capabilityID: capabilityID, serviceManager: serviceManager)
    }

    /// Whether a custom adapter is registered for this capability.
    func hasCustomAdapter(for capabilityID: String) -> Bool {
        factories[capabilityID] != nil
    }
}
