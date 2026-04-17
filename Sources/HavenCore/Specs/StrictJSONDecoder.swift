import Foundation

/// Helpers for strict JSON decoding that rejects unknown keys.
///
/// Swift's `JSONDecoder` silently ignores unknown keys by default and
/// there is no built-in flag to change that. The approach here is:
///
/// 1. Decode the raw JSON into an untyped dictionary.
/// 2. Compare the top-level keys against the known `CodingKey` set
///    for the target type.
/// 3. If any extra keys are found, report them as issues instead of
///    silently dropping them.
///
/// **Tradeoff**: This adds a second parse of the raw data (once as
/// `[String: Any]`, once via `Decodable`). For spec files that are
/// typically < 1 KB each, the overhead is negligible, and correctness
/// is more important than speed here.
enum StrictJSONDecoder {

    /// Decode `T` from `data`, collecting unknown-key issues.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` target.
    ///   - data: Raw JSON bytes.
    ///   - knownKeys: The set of top-level JSON keys that `T` expects.
    ///   - source: A label (usually the filename) used in issue messages.
    /// - Returns: A tuple of the decoded value (nil on failure) and any issues.
    static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        knownKeys: Set<String>,
        source: String
    ) -> (value: T?, issues: [SpecLoadIssue]) {
        var issues: [SpecLoadIssue] = []

        // --- Pass 1: check for unknown keys ---
        do {
            if let topLevel = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let extraKeys = Set(topLevel.keys).subtracting(knownKeys)
                for key in extraKeys.sorted() {
                    issues.append(SpecLoadIssue(
                        kind: .unknownField,
                        source: source,
                        detail: "Unknown field '\(key)'."
                    ))
                }
            }
        } catch {
            // Will be caught again in pass 2 as malformed JSON.
        }

        // --- Pass 2: actual decode ---
        let decoder = JSONDecoder()
        do {
            let value = try decoder.decode(type, from: data)
            return (value, issues)
        } catch {
            issues.append(SpecLoadIssue(
                kind: .malformedJSON,
                source: source,
                detail: error.localizedDescription
            ))
            return (nil, issues)
        }
    }
}

// MARK: - Known keys per spec type

extension StrictJSONDecoder {

    static let capabilityKeys: Set<String> = [
        "id", "name", "version", "description",
        "icon", "iconImage", "fullDescription", "notes", "screenshots"
    ]

    static let bundleKeys: Set<String> = [
        "id", "name", "capability", "runtimeUnits", "settings",
        "version", "instructions", "onboarding", "provisions", "storage"
    ]

    static let runtimeUnitKeys: Set<String> = [
        "id", "bundleID", "runtimeType", "installSource",
        "launchArguments", "healthcheck", "dependsOn", "port",
        "environment", "entrypoint", "version", "artifact", "python",
        "directories", "install", "dependencies"
    ]


    static let healthcheckKeys: Set<String> = [
        "type", "target", "intervalSeconds", "retries"
    ]

    static let pythonConfigKeys: Set<String> = [
        "package", "version", "entrypoint"
    ]

    static let pythonEntrypointKeys: Set<String> = [
        "module", "args"
    ]

    static let entrypointKeys: Set<String> = [
        "command", "args", "env"
    ]

    static let artifactKeys: Set<String> = [
        "type", "repo", "version", "assets", "archive"
    ]

    static let artifactAssetKeys: Set<String> = [
        "os", "arch", "file", "url", "sha256"
    ]

    static let onboardingKeys: Set<String> = [
        "steps"
    ]

    static let onboardingStepKeys: Set<String> = [
        "type", "title", "body", "fields", "url"
    ]

    static let onboardingFieldKeys: Set<String> = [
        "label", "value"
    ]

    static let provisionKeys: Set<String> = [
        "description", "source", "destination", "condition"
    ]

    static let installBlockKeys: Set<String> = [
        "steps"
    ]

    static let installStepKeys: Set<String> = [
        "action", "path", "source", "mode", "content", "ifNotExists"
    ]

    static let dependencyKeys: Set<String> = [
        "id", "kind", "required", "validateCommand", "description"
    ]

    static let storagePolicyKeys: Set<String> = [
        "persistent", "userVisible"
    ]

    /// Check a nested dictionary for unknown keys, appending issues.
    static func checkNestedKeys(
        in dict: [String: Any],
        knownKeys: Set<String>,
        source: String,
        issues: inout [SpecLoadIssue]
    ) {
        let extraKeys = Set(dict.keys).subtracting(knownKeys)
        for key in extraKeys.sorted() {
            issues.append(SpecLoadIssue(
                kind: .unknownField,
                source: source,
                detail: "Unknown field '\(key)'."
            ))
        }
    }
}
