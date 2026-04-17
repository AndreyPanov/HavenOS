import Foundation

/// Loads, decodes, and validates spec JSON files from a directory tree.
///
/// Expected layout under the root URL:
/// ```
/// <root>/
///   my-service/
///     capability.json   — single Capability object
///     bundle.json       — single Bundle object
///     runtimes.json     — JSON array of RuntimeUnit objects
/// ```
///
/// Usage:
/// ```swift
/// let result = SpecLoader.load(from: specsRootURL)
/// if result.succeeded {
///     let registry = result.registry!
///     // use registry.capabilitiesByID, etc.
/// } else {
///     for issue in result.issues { print(issue) }
/// }
/// ```
public enum SpecLoader {

    // MARK: - Public API

    /// Load all specs from the given root directory.
    ///
    /// The loader never throws. All problems are returned as
    /// ``SpecLoadIssue`` values inside the result.
    public static func load(from rootURL: URL) -> SpecLoadResult {
        var issues: [SpecLoadIssue] = []

        // Enumerate subdirectories of root — each is a service folder.
        let serviceFolders = enumerateServiceFolders(rootURL)

        var capabilities: [Capability] = []
        var bundles: [Bundle] = []
        var allRuntimeUnits: [RuntimeUnit] = []

        for folder in serviceFolders {
            let folderName = folder.lastPathComponent

            // capability.json — single object
            if var cap: Capability = decodeSingleSpec(
                Capability.self,
                file: folder.appendingPathComponent("capability.json"),
                knownKeys: StrictJSONDecoder.capabilityKeys,
                folderName: folderName,
                issues: &issues
            ) {
                // Resolve relative screenshot paths against the service folder.
                cap = resolveScreenshots(cap, serviceFolder: folder, issues: &issues)
                capabilities.append(cap)
            }

            // bundle.json — single object
            let bundleFile = folder.appendingPathComponent("bundle.json")
            if let bun: Bundle = decodeSingleSpec(
                Bundle.self,
                file: bundleFile,
                knownKeys: StrictJSONDecoder.bundleKeys,
                folderName: folderName,
                issues: &issues
            ) {
                checkBundleNestedKeys(file: bundleFile, folderName: folderName, issues: &issues)
                bundles.append(bun)
            }

            // runtimes.json — JSON array of RuntimeUnit objects
            let rawUnits = decodeRuntimeArray(
                file: folder.appendingPathComponent("runtimes.json"),
                folderName: folderName,
                issues: &issues
            )

            // Resolve relative installSource paths against the service folder.
            let resolvedUnits = resolveInstallSources(rawUnits, rootURL: folder, issues: &issues)
            allRuntimeUnits.append(contentsOf: resolvedUnits)
        }

        // --- Duplicate ID detection ---
        let capsByID = deduplicateByID(capabilities, kind: "Capability", issues: &issues)
        let bundlesByID = deduplicateByID(bundles, kind: "Bundle", issues: &issues)
        let unitsByID = deduplicateByID(allRuntimeUnits, kind: "RuntimeUnit", issues: &issues)

        // --- Cross-reference validation ---
        crossValidate(
            capsByID: capsByID,
            bundlesByID: bundlesByID,
            unitsByID: unitsByID,
            issues: &issues
        )

        // --- Per-model validation ---
        validateAll(capsByID.values, issues: &issues)
        validateAll(bundlesByID.values, issues: &issues)
        validateAll(unitsByID.values, issues: &issues)

        let hasErrors = issues.contains { $0.isError }

        if hasErrors {
            return SpecLoadResult(registry: nil, issues: issues)
        } else {
            let registry = SpecRegistry(
                capabilitiesByID: capsByID,
                bundlesByID: bundlesByID,
                runtimeUnitsByID: unitsByID
            )
            return SpecLoadResult(registry: registry, issues: issues)
        }
    }

    // MARK: - Internals

    /// Returns URLs for all immediate subdirectories of `rootURL`, sorted by name.
    private static func enumerateServiceFolders(_ rootURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Decode a single spec object from a well-known filename.
    /// Returns nil if the file does not exist (not every service folder must have all files).
    private static func decodeSingleSpec<T: Decodable & Identifiable>(
        _ type: T.Type,
        file: URL,
        knownKeys: Set<String>,
        folderName: String,
        issues: inout [SpecLoadIssue]
    ) -> T? where T.ID == String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return nil }

        let source = "\(folderName)/\(file.lastPathComponent)"
        guard let data = try? Data(contentsOf: file) else {
            issues.append(SpecLoadIssue(
                kind: .malformedJSON,
                source: source,
                detail: "Could not read file."
            ))
            return nil
        }
        let (value, fileIssues) = StrictJSONDecoder.decode(
            type, from: data, knownKeys: knownKeys, source: source
        )
        issues.append(contentsOf: fileIssues)
        return value
    }

    /// Decode an array of RuntimeUnit objects from runtime.json.
    /// Returns an empty array if the file does not exist.
    private static func decodeRuntimeArray(
        file: URL,
        folderName: String,
        issues: inout [SpecLoadIssue]
    ) -> [RuntimeUnit] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: file.path) else { return [] }

        let source = "\(folderName)/\(file.lastPathComponent)"
        guard let data = try? Data(contentsOf: file) else {
            issues.append(SpecLoadIssue(
                kind: .malformedJSON,
                source: source,
                detail: "Could not read file."
            ))
            return []
        }

        // Unknown-key check: parse as array of dictionaries first.
        do {
            if let topLevel = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for (index, dict) in topLevel.enumerated() {
                    let unitSource = "\(source)[\(index)]"

                    // Top-level keys
                    StrictJSONDecoder.checkNestedKeys(
                        in: dict, knownKeys: StrictJSONDecoder.runtimeUnitKeys,
                        source: unitSource, issues: &issues
                    )

                    // Nested: python block
                    if let pythonDict = dict["python"] as? [String: Any] {
                        StrictJSONDecoder.checkNestedKeys(
                            in: pythonDict, knownKeys: StrictJSONDecoder.pythonConfigKeys,
                            source: "\(unitSource).python", issues: &issues
                        )
                        // Nested: python.entrypoint
                        if let epDict = pythonDict["entrypoint"] as? [String: Any] {
                            StrictJSONDecoder.checkNestedKeys(
                                in: epDict, knownKeys: StrictJSONDecoder.pythonEntrypointKeys,
                                source: "\(unitSource).python.entrypoint", issues: &issues
                            )
                        }
                    }

                    // Nested: entrypoint block
                    if let epDict = dict["entrypoint"] as? [String: Any] {
                        StrictJSONDecoder.checkNestedKeys(
                            in: epDict, knownKeys: StrictJSONDecoder.entrypointKeys,
                            source: "\(unitSource).entrypoint", issues: &issues
                        )
                    }

                    // Nested: healthcheck block
                    if let hcDict = dict["healthcheck"] as? [String: Any] {
                        StrictJSONDecoder.checkNestedKeys(
                            in: hcDict, knownKeys: StrictJSONDecoder.healthcheckKeys,
                            source: "\(unitSource).healthcheck", issues: &issues
                        )
                    }

                    // Nested: install block
                    if let installDict = dict["install"] as? [String: Any] {
                        StrictJSONDecoder.checkNestedKeys(
                            in: installDict, knownKeys: StrictJSONDecoder.installBlockKeys,
                            source: "\(unitSource).install", issues: &issues
                        )
                        if let steps = installDict["steps"] as? [[String: Any]] {
                            for (si, stepDict) in steps.enumerated() {
                                StrictJSONDecoder.checkNestedKeys(
                                    in: stepDict, knownKeys: StrictJSONDecoder.installStepKeys,
                                    source: "\(unitSource).install.steps[\(si)]", issues: &issues
                                )
                            }
                        }
                    }

                    // Nested: dependencies array
                    if let deps = dict["dependencies"] as? [[String: Any]] {
                        for (di, depDict) in deps.enumerated() {
                            StrictJSONDecoder.checkNestedKeys(
                                in: depDict, knownKeys: StrictJSONDecoder.dependencyKeys,
                                source: "\(unitSource).dependencies[\(di)]", issues: &issues
                            )
                        }
                    }
                }
            }
        } catch {
            // Will be caught in decode pass below.
        }

        // Decode as [RuntimeUnit].
        let decoder = JSONDecoder()
        do {
            let units = try decoder.decode([RuntimeUnit].self, from: data)
            return units
        } catch {
            issues.append(SpecLoadIssue(
                kind: .malformedJSON,
                source: source,
                detail: error.localizedDescription
            ))
            return []
        }
    }

    /// Check nested keys in bundle.json (onboarding + provisions blocks).
    private static func checkBundleNestedKeys(
        file: URL,
        folderName: String,
        issues: inout [SpecLoadIssue]
    ) {
        guard let data = try? Data(contentsOf: file),
              let topLevel = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let source = "\(folderName)/\(file.lastPathComponent)"

        // Nested: onboarding block
        if let onboardingDict = topLevel["onboarding"] as? [String: Any] {
            StrictJSONDecoder.checkNestedKeys(
                in: onboardingDict, knownKeys: StrictJSONDecoder.onboardingKeys,
                source: "\(source).onboarding", issues: &issues
            )
            if let steps = onboardingDict["steps"] as? [[String: Any]] {
                for (index, stepDict) in steps.enumerated() {
                    StrictJSONDecoder.checkNestedKeys(
                        in: stepDict, knownKeys: StrictJSONDecoder.onboardingStepKeys,
                        source: "\(source).onboarding.steps[\(index)]", issues: &issues
                    )
                    // Nested: fields within each step
                    if let fields = stepDict["fields"] as? [[String: Any]] {
                        for (fi, fieldDict) in fields.enumerated() {
                            StrictJSONDecoder.checkNestedKeys(
                                in: fieldDict, knownKeys: StrictJSONDecoder.onboardingFieldKeys,
                                source: "\(source).onboarding.steps[\(index)].fields[\(fi)]", issues: &issues
                            )
                        }
                    }
                }
            }
        }

        // Nested: storage block
        if let storageDict = topLevel["storage"] as? [String: Any] {
            for (role, value) in storageDict {
                if let policyDict = value as? [String: Any] {
                    StrictJSONDecoder.checkNestedKeys(
                        in: policyDict, knownKeys: StrictJSONDecoder.storagePolicyKeys,
                        source: "\(source).storage.\(role)", issues: &issues
                    )
                }
            }
        }

        // Nested: provisions array
        if let provisions = topLevel["provisions"] as? [[String: Any]] {
            for (index, provDict) in provisions.enumerated() {
                StrictJSONDecoder.checkNestedKeys(
                    in: provDict, knownKeys: StrictJSONDecoder.provisionKeys,
                    source: "\(source).provisions[\(index)]", issues: &issues
                )
            }
        }
    }

    /// Collect items into a dictionary keyed by ID, flagging duplicates.
    private static func deduplicateByID<T: Identifiable>(
        _ items: [T],
        kind: String,
        issues: inout [SpecLoadIssue]
    ) -> [String: T] where T.ID == String {
        var dict: [String: T] = [:]
        for item in items {
            if dict[item.id] != nil {
                issues.append(SpecLoadIssue(
                    kind: .duplicateID,
                    source: item.id,
                    detail: "Duplicate \(kind) ID '\(item.id)'."
                ))
            } else {
                dict[item.id] = item
            }
        }
        return dict
    }

    /// Verify cross-references between the three spec types.
    private static func crossValidate(
        capsByID: [String: Capability],
        bundlesByID: [String: Bundle],
        unitsByID: [String: RuntimeUnit],
        issues: inout [SpecLoadIssue]
    ) {
        // Bundle → Capability
        for bundle in bundlesByID.values {
            if capsByID[bundle.capability] == nil {
                issues.append(SpecLoadIssue(
                    kind: .missingReference,
                    source: bundle.id,
                    detail: "Bundle references unknown capability '\(bundle.capability)'."
                ))
            }
            // Bundle → RuntimeUnit
            for unitID in bundle.runtimeUnits {
                if unitsByID[unitID] == nil {
                    issues.append(SpecLoadIssue(
                        kind: .missingReference,
                        source: bundle.id,
                        detail: "Bundle references unknown runtime unit '\(unitID)'."
                    ))
                }
            }
        }

        // RuntimeUnit → Bundle
        for unit in unitsByID.values {
            if bundlesByID[unit.bundleID] == nil {
                issues.append(SpecLoadIssue(
                    kind: .missingReference,
                    source: unit.id,
                    detail: "RuntimeUnit references unknown bundle '\(unit.bundleID)'."
                ))
            }
        }
    }

    /// Resolve relative image paths (iconImage + screenshots) against the service folder.
    ///
    /// Absolute paths are kept as-is. Relative paths are resolved from
    /// `serviceFolder`. Missing files produce a non-fatal warning.
    private static func resolveScreenshots(
        _ capability: Capability,
        serviceFolder: URL,
        issues: inout [SpecLoadIssue]
    ) -> Capability {
        let fm = FileManager.default
        let hasImages = capability.iconImage != nil || !capability.screenshots.isEmpty
        guard hasImages else { return capability }

        // Resolve iconImage
        var resolvedIcon: String? = nil
        if let iconFile = capability.iconImage {
            if iconFile.hasPrefix("http://") || iconFile.hasPrefix("https://") {
                resolvedIcon = iconFile
            } else if iconFile.hasPrefix("/") {
                resolvedIcon = iconFile
            } else {
                let path = serviceFolder.appendingPathComponent(iconFile).path
                if !fm.fileExists(atPath: path) {
                    issues.append(SpecLoadIssue(
                        kind: .validationFailure,
                        source: capability.id,
                        detail: "Icon image file does not exist: '\(path)' (from '\(iconFile)').",
                        severity: .warning
                    ))
                }
                resolvedIcon = path
            }
        }

        // Resolve screenshots
        let resolvedScreenshots = capability.screenshots.map { filename -> String in
            if filename.hasPrefix("http://") || filename.hasPrefix("https://") { return filename }
            if filename.hasPrefix("/") { return filename }
            let path = serviceFolder.appendingPathComponent(filename).path
            if !fm.fileExists(atPath: path) {
                issues.append(SpecLoadIssue(
                    kind: .validationFailure,
                    source: capability.id,
                    detail: "Screenshot file does not exist: '\(path)' (from '\(filename)').",
                    severity: .warning
                ))
            }
            return path
        }

        return capability.withResolvedImages(
            iconImage: resolvedIcon,
            screenshots: resolvedScreenshots
        )
    }

    /// Resolve relative `installSource` paths against the service folder.
    ///
    /// - Paths starting with `/` are treated as absolute and kept as-is.
    /// - All other paths are resolved relative to `rootURL` (the service folder).
    /// - If the resolved path does not exist on disk, a warning is emitted.
    private static func resolveInstallSources(
        _ units: [RuntimeUnit],
        rootURL: URL,
        issues: inout [SpecLoadIssue]
    ) -> [RuntimeUnit] {
        let fm = FileManager.default
        return units.map { unit in
            let source = unit.installSource
            if source.hasPrefix("/") {
                // Absolute path — keep as-is.
                return unit
            }
            // Relative path — resolve from service folder.
            let resolved = rootURL.appendingPathComponent(source).path
            if !fm.fileExists(atPath: resolved) {
                issues.append(SpecLoadIssue(
                    kind: .validationFailure,
                    source: unit.id,
                    detail: "installSource path does not exist: '\(resolved)' (resolved from '\(source)').",
                    severity: .warning
                ))
            }
            return unit.withInstallSource(resolved)
        }
    }

    /// Run each model's own `validate()` and collect failures.
    private static func validateAll<T: Identifiable>(
        _ items: some Collection<T>,
        issues: inout [SpecLoadIssue]
    ) where T.ID == String {
        for item in items {
            // Use protocol witness to call validate() where available.
            if let validatable = item as? any Validatable {
                do {
                    try validatable.validate()
                } catch let error as ValidationError {
                    issues.append(SpecLoadIssue(
                        kind: .validationFailure,
                        source: item.id,
                        detail: error.message
                    ))
                } catch {
                    issues.append(SpecLoadIssue(
                        kind: .validationFailure,
                        source: item.id,
                        detail: error.localizedDescription
                    ))
                }
            }
        }
    }
}

// MARK: - Validatable protocol

/// Internal protocol so SpecLoader can call `validate()` generically.
protocol Validatable {
    func validate() throws
}

extension Capability: Validatable {}
extension Bundle: Validatable {}
extension RuntimeUnit: Validatable {}
