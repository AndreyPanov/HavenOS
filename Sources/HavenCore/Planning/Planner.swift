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
        let persistedSettings = resolvedSettings.filter { key, _ in
            bundle.settings.first { $0.key == key }?.sensitive != true
        }

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

        // 8. Build service-level context from all units
        var serviceContextValues = resolvedSettings
        serviceContextValues["data_dir"] = layout.data.path
        serviceContextValues["config_dir"] = layout.config.path
        serviceContextValues["logs_dir"] = layout.logs.path
        serviceContextValues["run_dir"] = layout.run.path
        serviceContextValues["service_root"] = layout.serviceRoot.path
        if let firstPort = plannedUnits.compactMap({ $0.port?.number }).first {
            serviceContextValues["port"] = String(firstPort)
        }
        // Merge directory variables from all units into the service context.
        for unit in plannedUnits {
            for (key, value) in unit.templateContext.values where key.hasSuffix("_dir") {
                serviceContextValues[key] = value
            }
        }
        // Merge per-unit port variables (e.g. db_port from unit with port 5432
        // mapped via the "db_port" setting key).
        for unit in plannedUnits {
            if let portNum = unit.port?.number {
                serviceContextValues["\(unit.spec.id).port"] = String(portNum)
            }
        }

        // 9. Expand shared directories from bundle
        for (role, rawPath) in bundle.sharedDirectories {
            let settingsCtx = TemplateContext(values: serviceContextValues)
            let expandedPath = settingsCtx.expand(rawPath)
            let resolvedPath: String
            if expandedPath.hasPrefix("/") {
                resolvedPath = expandedPath
            } else {
                resolvedPath = layout.serviceRoot
                    .appendingPathComponent(expandedPath).path
            }
            serviceContextValues["shared_\(role)_dir"] = resolvedPath
        }

        let serviceContext = TemplateContext(values: serviceContextValues)

        // 10. Expand shared environment and merge into each unit
        let expandedSharedEnv = serviceContext.expandValues(in: bundle.sharedEnvironment)
        if !expandedSharedEnv.isEmpty {
            plannedUnits = plannedUnits.map { unit in
                // Unit-level env wins on conflict (override pattern)
                var mergedEnv = expandedSharedEnv
                for (key, value) in unit.resolvedEnvironment {
                    mergedEnv[key] = value
                }
                return PlannedRuntimeUnit(
                    spec: unit.spec,
                    resolvedLaunchArguments: unit.resolvedLaunchArguments,
                    resolvedEnvironment: mergedEnv,
                    port: unit.port,
                    resolvedHealthcheck: unit.resolvedHealthcheck,
                    dependsOn: unit.dependsOn,
                    templateContext: unit.templateContext,
                    resolvedDirectories: unit.resolvedDirectories,
                    resolvedInstall: unit.resolvedInstall,
                    resolvedReadinessProbe: unit.resolvedReadinessProbe
                )
            }
        }

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
            resolvedSettings: persistedSettings,
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
            var value: String?
            if let userValue = userSettings[field.key] {
                value = userValue
            } else if let defaultValue = field.defaultValue {
                value = defaultValue
            } else if field.required {
                throw PlanningError.requiredSettingMissing(
                    key: field.key,
                    bundleID: bundle.id
                )
            }
            // Optional field with no default and no user value → omitted

            // Expand tilde in path-type settings so downstream code sees absolute paths
            if let v = value {
                if field.fieldType == .path && v.hasPrefix("~") {
                    resolved[field.key] = NSString(string: v).expandingTildeInPath
                } else {
                    resolved[field.key] = v
                }
            }
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

        let portSettingKey = portSettingKey(for: unit, resolvedSettings: resolvedSettings)
        if let specPort = unit.port {
            if let portSettingKey,
               let portOverride = resolvedSettings[portSettingKey].flatMap(Int.init),
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
            if let portSettingKey {
                contextValues[portSettingKey] = String(port.number)
            }
        }

        // Expand spec-declared directories into template variables.
        // First pass: expand setting references in directory values.
        let settingsContext = TemplateContext(values: contextValues)
        for (role, rawPath) in unit.directories {
            let expandedPath = settingsContext.expand(rawPath)
            let resolvedPath: String
            if expandedPath.hasPrefix("~") {
                resolvedPath = NSString(string: expandedPath).expandingTildeInPath
            } else if expandedPath.hasPrefix("/") {
                resolvedPath = expandedPath
            } else {
                resolvedPath = layout.serviceRoot
                    .appendingPathComponent(expandedPath).path
            }
            contextValues["\(role)_dir"] = resolvedPath
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

        // Build resolved directories map from context
        var resolvedDirs: [String: String] = [:]
        for role in unit.directories.keys {
            if let path = contextValues["\(role)_dir"] {
                resolvedDirs[role] = path
            }
        }

        // Expand install steps
        let resolvedInstall = unit.install.map { context.expand($0) }

        // Expand readiness probe
        let resolvedReadinessProbe = unit.readinessProbe.map { context.expand($0) }

        return PlannedRuntimeUnit(
            spec: unit,
            resolvedLaunchArguments: resolvedArgs,
            resolvedEnvironment: resolvedEnv,
            port: port,
            resolvedHealthcheck: resolvedHealthcheck,
            dependsOn: unit.dependsOn,
            templateContext: context,
            resolvedDirectories: resolvedDirs,
            resolvedInstall: resolvedInstall,
            resolvedReadinessProbe: resolvedReadinessProbe
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

    /// Resolve which setting key controls a unit's port.
    ///
    /// The legacy single-unit convention is `port`. Multi-unit specs use
    /// named settings such as `db_port` and `http_port`; we bind those by
    /// looking for a referenced `*_port` key on the unit, falling back to a
    /// single setting whose default value matches the unit's spec port.
    private static func portSettingKey(
        for unit: RuntimeUnit,
        resolvedSettings: [String: String]
    ) -> String? {
        guard unit.port != nil else { return nil }
        if resolvedSettings["port"].flatMap(Int.init) != nil {
            return "port"
        }

        let portKeys = resolvedSettings.keys
            .filter { $0.hasSuffix("_port") && resolvedSettings[$0].flatMap(Int.init) != nil }
            .sorted()
        let referenced = portKeys.filter { references(settingKey: $0, in: unit) }
        if referenced.count == 1 {
            return referenced[0]
        }

        if let specPort = unit.port {
            let matchingDefaults = portKeys.filter {
                resolvedSettings[$0].flatMap(Int.init) == specPort
            }
            if matchingDefaults.count == 1 {
                return matchingDefaults[0]
            }
        }

        return nil
    }

    private static func references(settingKey key: String, in unit: RuntimeUnit) -> Bool {
        let token = "${\(key)}"
        var strings = unit.launchArguments
        strings.append(contentsOf: unit.environment.values)
        strings.append(contentsOf: unit.directories.values)
        if let install = unit.install {
            strings.append(contentsOf: install.steps.flatMap { step in
                [step.path, step.source, step.mode, step.content].compactMap { $0 }
            })
        }

        if strings.contains(where: { $0.contains(token) }) {
            return true
        }
        if unit.healthcheck?.target.contains(token) == true {
            return true
        }
        if unit.readinessProbe?.target.contains(token) == true {
            return true
        }
        return false
    }
}
