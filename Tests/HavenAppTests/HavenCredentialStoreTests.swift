import Foundation
import Testing
@testable import HavenAppKit

@Suite("Haven credential store")
@MainActor
struct HavenCredentialStoreTests {
    @Test("stores, updates, and deletes credentials in UserDefaults")
    func storePersistsCredentialLifecycle() {
        let capabilityID = "haven.test.credentials.\(UUID().uuidString)"
        let suiteName = "haven.credentials.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = HavenCredentialStore(defaults: defaults)
        defer {
            store.removeAll(for: capabilityID)
            defaults.removePersistentDomain(forName: suiteName)
        }

        #expect(store.string(for: .kavita, .password, capabilityID: capabilityID) == nil)

        #expect(store.set("first-secret", for: .kavita, .password, capabilityID: capabilityID))
        #expect(store.string(for: .kavita, .password, capabilityID: capabilityID) == "first-secret")

        #expect(store.set("second-secret", for: .kavita, .password, capabilityID: capabilityID))
        #expect(store.string(for: .kavita, .password, capabilityID: capabilityID) == "second-secret")

        store.remove(for: .kavita, .password, capabilityID: capabilityID)

        #expect(store.string(for: .kavita, .password, capabilityID: capabilityID) == nil)
    }

    @Test("migration is a no-op for UserDefaults-backed credentials")
    func migrationKeepsUserDefaultsCredentials() {
        let capabilityID = "haven.test.credentials.\(UUID().uuidString)"
        let suiteName = "haven.credentials.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = HavenCredentialStore(defaults: defaults)
        defer {
            store.removeAll(for: .navidrome, capabilityID: capabilityID)
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("secret", forKey: "haven.navidrome.password.\(capabilityID)")

        store.migrateLegacyCredentials(for: .navidrome, capabilityID: capabilityID)

        #expect(store.string(for: .navidrome, .password, capabilityID: capabilityID) == "secret")
        #expect(defaults.string(forKey: "haven.navidrome.password.\(capabilityID)") == "secret")
    }

    @Test("backup snapshot emits UserDefaults credential keys")
    func backupSnapshotUsesCredentialKeys() {
        let capabilityID = "haven.test.credentials.\(UUID().uuidString)"
        let suiteName = "haven.credentials.\(UUID().uuidString)"
        let store = HavenCredentialStore(defaults: UserDefaults(suiteName: suiteName)!)
        defer {
            store.removeAll(for: .filebrowser, capabilityID: capabilityID)
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }

        store.set("haven", for: .filebrowser, .username, capabilityID: capabilityID)
        store.set("secret", for: .filebrowser, .password, capabilityID: capabilityID)

        let snapshot = store.backupSnapshot(for: .filebrowser, capabilityID: capabilityID)

        #expect(snapshot.values["haven.filebrowser.username.\(capabilityID)"] == .string("haven"))
        #expect(snapshot.values["haven.filebrowser.password.\(capabilityID)"] == .string("secret"))
    }

}
