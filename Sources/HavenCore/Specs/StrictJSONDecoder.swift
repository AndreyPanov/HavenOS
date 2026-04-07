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
        "id", "name", "version", "description"
    ]

    static let bundleKeys: Set<String> = [
        "id", "name", "capability", "runtimeUnits", "settings",
        "version"
    ]

    static let runtimeUnitKeys: Set<String> = [
        "id", "bundleID", "runtimeType", "installSource",
        "launchArguments", "healthcheck", "dependsOn", "port",
        "environment", "entrypoint", "version", "artifact", "python"
    ]


    static let healthcheckKeys: Set<String> = [
        "type", "target", "intervalSeconds", "retries"
    ]
}
