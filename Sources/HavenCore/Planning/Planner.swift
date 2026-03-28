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
        baseDirectory: URL
    ) throws -> InstallPlan {
        // 1. Resolve capability
        guard let capability = registry.capabilitiesByID[capabilityID] else {
            throw PlanningError.capabilityNotFound(id: capabilityID)
        }

        // 2. Find the bundle that implements this capability
        guard let bundle = registry.bundlesByID.values.first(
            where: { $0.capabilityID == capabilityID }
        ) else {
            throw PlanningError.bundleNotFound(capabilityID: capabilityID)
        }

        // 3. Resolve all runtime units
        var units: [RuntimeUnit] = []
        for unitID in bundle.runtimeUnitIDs {
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
        let layout = PlannedDirectoryLayout(
            baseDirectory: baseDirectory,
            capabilityID: capabilityID
        )

        // 6. Topological sort of runtime units by dependsOn
        let sortedUnits = try topologicalSort(units)

        // 7. Plan each runtime unit with template expansion
        let plannedUnits = sortedUnits.map { unit in
            planUnit(unit, resolvedSettings: resolvedSettings, layout: layout)
        }

        let service = PlannedService(
            capability: capability,
            bundle: bundle,
            units: plannedUnits,
            resolvedSettings: resolvedSettings,
            directoryLayout: layout
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
    private static func planUnit(
        _ unit: RuntimeUnit,
        resolvedSettings: [String: String],
        layout: PlannedDirectoryLayout
    ) -> PlannedRuntimeUnit {
        // Determine port
        let port: PlannedPort?
        if let portOverride = resolvedSettings["port"].flatMap(Int.init) {
            if unit.port != nil && portOverride != unit.port {
                port = PlannedPort(number: portOverride, source: .settingOverride)
            } else if let specPort = unit.port {
                port = PlannedPort(number: specPort, source: .spec)
            } else {
                port = PlannedPort(number: portOverride, source: .settingOverride)
            }
        } else if let specPort = unit.port {
            port = PlannedPort(number: specPort, source: .spec)
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
}
