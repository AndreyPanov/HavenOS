import Foundation

/// Pure planner that resolves intent into a concrete, deterministic install plan.
///
/// The planner is the "brain" of Haven: given a capability ID, a registry
/// of specs, user settings, and a base directory, it produces an
/// ``InstallPlan`` that later execution layers can apply.
///
/// It performs no I/O, no file creation, no downloads, no process execution.
public enum Planner {

    // MARK: - Public API

    /// Plan the installation of a capability.
    ///
    /// - Parameters:
    ///   - capabilityID: The ID of the capability to install.
    ///   - registry: The loaded spec registry.
    ///   - settings: User-provided setting overrides (key → value).
    ///   - baseDirectory: Root directory under which service directories are created.
    /// - Returns: A fully resolved ``InstallPlan``.
    /// - Throws: ``PlanningError`` if the plan cannot be constructed.
    public static func planInstall(
        capabilityID: String,
        registry: SpecRegistry,
        settings: [String: String] = [:],
        baseDirectory: URL,
        usedPorts: Set<Int> = []
    ) throws -> InstallPlan {
        // 1. Resolve capability
        guard let capability = registry.capabilitiesByID[capabilityID] else {
            throw PlanningError.capabilityNotFound(id: capabilityID)
        }

        // 2. Find the bundle that implements this capability
        guard let bundle = registry.bundlesByID.values.first(
            where: { $0.capability == capabilityID }
        ) else {
            throw PlanningError.bundleNotFound(capabilityID: capabilityID)
        }

        // 3. Resolve all runtime units
        var units: [RuntimeUnit] = []
        for unitID in bundle.runtimeUnits {
            guard let unit = registry.runtimeUnitsByID[unitID] else {
                throw PlanningError.runtimeUnitNotFound(id: unitID, bundleID: bundle.id)
            }
            units.append(unit)
        }

        // 4. Resolve settings: merge user overrides with defaults
        let resolvedSettings = try resolveSettings(
            bundle: bundle,
            userSettings: settings
        )

        // 5. Directory layout
        let layout = ServiceDirectoryLayout(
            baseDirectory: baseDirectory,
            capabilityID: capabilityID
        )

        // 6. Topological sort of runtime units by dependsOn
        let sortedUnits = try topologicalSort(units)

        // 7. Plan each runtime unit with template expansion and port conflict avoidance
        var assignedPorts = usedPorts
        var plannedUnits: [PlannedRuntimeUnit] = []
        for unit in sortedUnits {
            let planned = try planUnit(
                unit, resolvedSettings: resolvedSettings,
                layout: layout, usedPorts: assignedPorts
            )
            if let port = planned.port {
                assignedPorts.insert(port.number)
            }
            plannedUnits.append(planned)
        }

        // 8. Resolve onboarding and provisions using a service-level context
        var serviceContextValues = resolvedSettings
        serviceContextValues["data_dir"] = layout.data.path
        serviceContextValues["config_dir"] = layout.config.path
        serviceContextValues["logs_dir"] = layout.logs.path
        serviceContextValues["run_dir"] = layout.run.path
        serviceContextValues["service_root"] = layout.serviceRoot.path
        if let firstPort = plannedUnits.compactMap({ $0.port?.number }).first {
            serviceContextValues["port"] = String(firstPort)
        }
        let serviceContext = TemplateContext(values: serviceContextValues)

        let resolvedOnboarding = bundle.onboarding.map { serviceContext.expand($0) }

        let resolvedProvisions = bundle.provisions
            .filter { provision in
                guard let conditionKey = provision.condition else { return true }
                return resolvedSettings[conditionKey]?.lowercased() == "true"
            }
            .map { serviceContext.expand($0) }

        let service = PlannedService(
            capability: capability,
            bundle: bundle,
            units: plannedUnits,
            resolvedSettings: resolvedSettings,
            directoryLayout: layout,
            resolvedOnboarding: resolvedOnboarding,
            resolvedProvisions: resolvedProvisions
        )

        return InstallPlan(service: service)
    }

    // MARK: - Settings resolution

    /// Merge user overrides with bundle defaults, enforcing required fields.
    private static func resolveSettings(
        bundle: Bundle,
        userSettings: [String: String]
    ) throws -> [String: String] {
        var resolved: [String: String] = [:]

        for field in bundle.settings {
            if let userValue = userSettings[field.key] {
                resolved[field.key] = userValue
            } else if let defaultValue = field.defaultValue {
                resolved[field.key] = defaultValue
            } else if field.required {
                throw PlanningError.requiredSettingMissing(
                    key: field.key,
                    bundleID: bundle.id
                )
            }
            // Optional field with no default and no user value → omitted
        }

        return resolved
    }

    // MARK: - Topological sort

    /// Sort runtime units so that dependencies come before dependents.
    /// Throws ``PlanningError/dependencyCycle`` if a cycle is detected.
    private static func topologicalSort(_ units: [RuntimeUnit]) throws -> [RuntimeUnit] {
        let byID = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0) })
        var visited: Set<String> = []
        var inStack: Set<String> = []
        var order: [RuntimeUnit] = []

        func visit(_ id: String, ancestors: [String]) throws {
            if inStack.contains(id) {
                // Build the cycle path from where it started
                let cycleStart = ancestors.firstIndex(of: id) ?? ancestors.startIndex
                let cycle = Array(ancestors[cycleStart...]) + [id]
                throw PlanningError.dependencyCycle(unitIDs: cycle)
            }
            guard !visited.contains(id) else { return }
            guard let unit = byID[id] else { return }

            inStack.insert(id)
            for dep in unit.dependsOn {
                if byID[dep] != nil {
                    try visit(dep, ancestors: ancestors + [id])
                }
            }
            inStack.remove(id)
            visited.insert(id)
            order.append(unit)
        }

        for unit in units {
            try visit(unit.id, ancestors: [])
        }

        return order
    }

    // MARK: - Unit planning

    /// Build a ``PlannedRuntimeUnit`` by expanding templates and assigning ports.
    ///
    /// If the resolved port conflicts with a port in `usedPorts`, the planner
    /// automatically assigns the next available port.
    private static func planUnit(
        _ unit: RuntimeUnit,
        resolvedSettings: [String: String],
        layout: ServiceDirectoryLayout,
        usedPorts: Set<Int>
    ) throws -> PlannedRuntimeUnit {
        // Determine candidate port and its source.
        // Only units that declare a port in their spec get a PlannedPort.
        // The "port" setting provides a template value for ${port} expansion
        // but does not add a port to units that don't listen on one.
        let candidatePort: Int?
        let candidateSource: PlannedPort.Source

        if let specPort = unit.port {
            if let portOverride = resolvedSettings["port"].flatMap(Int.init),
               portOverride != specPort {
                candidatePort = portOverride
                candidateSource = .settingOverride
            } else {
                candidatePort = specPort
                candidateSource = .spec
            }
        } else {
            candidatePort = nil
            candidateSource = .spec // unused when candidatePort is nil
        }

        // Resolve conflicts: if the candidate port is already taken, find the next free one
        let port: PlannedPort?
        if let candidate = candidatePort {
            if !usedPorts.contains(candidate) {
                port = PlannedPort(number: candidate, source: candidateSource)
            } else {
                let resolved = try nextAvailablePort(
                    from: candidate, usedPorts: usedPorts, unitID: unit.id
                )
                port = PlannedPort(number: resolved, source: .autoAssigned)
            }
        } else {
            port = nil
        }

        // Build template context
        var contextValues = resolvedSettings
        contextValues["data_dir"] = layout.data.path
        contextValues["config_dir"] = layout.config.path
        contextValues["logs_dir"] = layout.logs.path
        contextValues["run_dir"] = layout.run.path
        contextValues["service_root"] = layout.serviceRoot.path
        if let port {
            contextValues["port"] = String(port.number)
        }
        let context = TemplateContext(values: contextValues)

        // Expand templates
        let resolvedArgs = context.expandAll(unit.launchArguments)
        let resolvedEnv = context.expandValues(in: unit.environment)

        // Expand healthcheck target
        let resolvedHealthcheck: Healthcheck?
        if let hc = unit.healthcheck {
            resolvedHealthcheck = Healthcheck(
                type: hc.type,
                target: context.expand(hc.target),
                intervalSeconds: hc.intervalSeconds,
                retries: hc.retries
            )
        } else {
            resolvedHealthcheck = nil
        }

        return PlannedRuntimeUnit(
            spec: unit,
            resolvedLaunchArguments: resolvedArgs,
            resolvedEnvironment: resolvedEnv,
            port: port,
            resolvedHealthcheck: resolvedHealthcheck,
            dependsOn: unit.dependsOn,
            templateContext: context
        )
    }

    // MARK: - Port conflict resolution

    /// Find the next available port starting from `start + 1`.
    ///
    /// Searches upward through unprivileged ports (1024–65535), wrapping
    /// around if necessary. Throws if every port in the range is taken.
    private static func nextAvailablePort(
        from start: Int,
        usedPorts: Set<Int>,
        unitID: String
    ) throws -> Int {
        let range = 1024...65535
        var candidate = start + 1
        if candidate > range.upperBound { candidate = range.lowerBound }
        let initial = candidate
        repeat {
            if !usedPorts.contains(candidate) {
                return candidate
            }
            candidate += 1
            if candidate > range.upperBound { candidate = range.lowerBound }
        } while candidate != initial
        throw PlanningError.noAvailablePorts(unitID: unitID)
    }
}
