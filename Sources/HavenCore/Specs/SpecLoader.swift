import Foundation

/// Loads, decodes, and validates spec JSON files from a directory tree.
///
/// Expected layout under the root URL:
/// ```
/// <root>/
///   Capabilities/   *.json  →  Capability
///   Bundles/         *.json  →  Bundle
///   Runtime/         *.json  →  RuntimeUnit
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

        let capabilities = decodeSpecs(
            Capability.self,
            directory: rootURL.appendingPathComponent("Capabilities"),
            knownKeys: StrictJSONDecoder.capabilityKeys,
            issues: &issues
        )
        let bundles = decodeSpecs(
            Bundle.self,
            directory: rootURL.appendingPathComponent("Bundles"),
            knownKeys: StrictJSONDecoder.bundleKeys,
            issues: &issues
        )
        let rawRuntimeUnits = decodeSpecs(
            RuntimeUnit.self,
            directory: rootURL.appendingPathComponent("Runtime"),
            knownKeys: StrictJSONDecoder.runtimeUnitKeys,
            issues: &issues
        )

        // --- Resolve relative installSource paths ---
        let runtimeUnits = resolveInstallSources(rawRuntimeUnits, rootURL: rootURL, issues: &issues)

        // --- Duplicate ID detection ---
        let capsByID = deduplicateByID(capabilities, kind: "Capability", issues: &issues)
        let bundlesByID = deduplicateByID(bundles, kind: "Bundle", issues: &issues)
        let unitsByID = deduplicateByID(runtimeUnits, kind: "RuntimeUnit", issues: &issues)

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

        if issues.isEmpty {
            let registry = SpecRegistry(
                capabilitiesByID: capsByID,
                bundlesByID: bundlesByID,
                runtimeUnitsByID: unitsByID
            )
            return SpecLoadResult(registry: registry, issues: [])
        } else {
            return SpecLoadResult(registry: nil, issues: issues)
        }
    }

    // MARK: - Internals

    /// Read every `.json` file in `directory`, strict-decode each one.
    private static func decodeSpecs<T: Decodable & Identifiable>(
        _ type: T.Type,
        directory: URL,
        knownKeys: Set<String>,
        issues: inout [SpecLoadIssue]
    ) -> [T] where T.ID == String {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            // Directory may not exist — that is fine (no specs of this kind).
            return []
        }

        let jsonFiles = contents
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var results: [T] = []
        for fileURL in jsonFiles {
            let filename = fileURL.lastPathComponent
            guard let data = try? Data(contentsOf: fileURL) else {
                issues.append(SpecLoadIssue(
                    kind: .malformedJSON,
                    source: filename,
                    detail: "Could not read file."
                ))
                continue
            }
            let (value, fileIssues) = StrictJSONDecoder.decode(
                type, from: data, knownKeys: knownKeys, source: filename
            )
            issues.append(contentsOf: fileIssues)
            if let value { results.append(value) }
        }
        return results
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

    /// Resolve relative `installSource` paths against the specs root directory.
    ///
    /// - Paths starting with `/` are treated as absolute and kept as-is.
    /// - All other paths are resolved relative to `rootURL`.
    /// - If the resolved path does not exist on disk, a `.validationFailure` is emitted.
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
            // Relative path — resolve from specs root.
            let resolved = rootURL.appendingPathComponent(source).path
            if !fm.fileExists(atPath: resolved) {
                issues.append(SpecLoadIssue(
                    kind: .validationFailure,
                    source: unit.id,
                    detail: "installSource path does not exist: '\(resolved)' (resolved from '\(source)')."
                ))
            }
            return RuntimeUnit(
                id: unit.id,
                bundleID: unit.bundleID,
                runtimeType: unit.runtimeType,
                installSource: resolved,
                launchArguments: unit.launchArguments,
                healthcheck: unit.healthcheck,
                dependsOn: unit.dependsOn,
                port: unit.port,
                environment: unit.environment,
                version: unit.version
            )
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
