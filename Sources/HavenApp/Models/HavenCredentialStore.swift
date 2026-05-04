import Foundation
import HavenBackup

package enum HavenCredentialBackend: String, CaseIterable, Sendable {
    case kavita
    case navidrome
    case jellyfin
    case filebrowser

    var legacyPrefix: String {
        "haven.\(rawValue)."
    }
}

package enum HavenCredentialPurpose: String, CaseIterable, Sendable {
    case token
    case username
    case password
    case managedUser
    case managedPass
    case apiKey

    var legacyName: String {
        rawValue
    }
}

package struct HavenCredentialSnapshot: Sendable, Equatable {
    package let values: [String: BackupCredentialValue]
}

@MainActor
package final class HavenCredentialStore {
    package static let shared = HavenCredentialStore()

    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    package func string(
        for backend: HavenCredentialBackend,
        _ purpose: HavenCredentialPurpose,
        capabilityID: String
    ) -> String? {
        defaults.string(forKey: legacyKey(
            backend: backend,
            purpose: purpose,
            capabilityID: capabilityID
        ))
    }

    @discardableResult
    package func set(
        _ value: String,
        for backend: HavenCredentialBackend,
        _ purpose: HavenCredentialPurpose,
        capabilityID: String
    ) -> Bool {
        defaults.set(
            value,
            forKey: legacyKey(
                backend: backend,
                purpose: purpose,
                capabilityID: capabilityID
            )
        )
        return true
    }

    package func remove(
        for backend: HavenCredentialBackend,
        _ purpose: HavenCredentialPurpose,
        capabilityID: String
    ) {
        defaults.removeObject(forKey: legacyKey(
            backend: backend,
            purpose: purpose,
            capabilityID: capabilityID
        ))
    }

    package func removeAll(for backend: HavenCredentialBackend, capabilityID: String) {
        for purpose in HavenCredentialPurpose.allCases {
            remove(for: backend, purpose, capabilityID: capabilityID)
        }
    }

    package func removeAll(for capabilityID: String) {
        for backend in HavenCredentialBackend.allCases {
            removeAll(for: backend, capabilityID: capabilityID)
        }
    }

    package func migrateLegacyCredentials(
        for _: HavenCredentialBackend,
        capabilityID _: String
    ) {
        // Credentials already live at the legacy UserDefaults keys again.
    }

    package func backupSnapshot(
        for backend: HavenCredentialBackend,
        capabilityID: String
    ) -> HavenCredentialSnapshot {
        var values: [String: BackupCredentialValue] = [:]

        for purpose in HavenCredentialPurpose.allCases {
            guard let value = string(
                for: backend,
                purpose,
                capabilityID: capabilityID
            ) else {
                continue
            }
            values[legacyKey(
                backend: backend,
                purpose: purpose,
                capabilityID: capabilityID
            )] = .string(value)
        }

        return HavenCredentialSnapshot(values: values)
    }

    package func legacyKey(
        backend: HavenCredentialBackend,
        purpose: HavenCredentialPurpose,
        capabilityID: String
    ) -> String {
        "\(backend.legacyPrefix)\(purpose.legacyName).\(capabilityID)"
    }
}
