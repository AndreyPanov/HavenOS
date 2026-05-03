import Foundation
import Observation
import Sparkle

@MainActor
@Observable
package final class AppUpdateModel {
    package let isConfigured: Bool
    package let configurationMessage: String?
    package private(set) var canCheckForUpdates = false

    @ObservationIgnored private let updaterController: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    package init(bundle: Bundle = .main) {
        let configuration = AppUpdateConfiguration(bundle: bundle)
        self.isConfigured = configuration.isConfigured
        self.configurationMessage = configuration.message

        if configuration.isConfigured {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            self.updaterController = controller
            self.canCheckForUpdates = controller.updater.canCheckForUpdates

            self.canCheckObservation = controller.updater.observe(
                \.canCheckForUpdates,
                options: [.initial, .new]
            ) { [weak self] _, change in
                let canCheckForUpdates = change.newValue ?? false
                Task { @MainActor [weak self] in
                    self?.canCheckForUpdates = canCheckForUpdates
                }
            }
        } else {
            self.updaterController = nil
        }
    }

    package func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updaterController?.updater.checkForUpdates()
    }
}

private struct AppUpdateConfiguration {
    let isConfigured: Bool
    let message: String?

    init(bundle: Bundle) {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String

        if feedURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            self.isConfigured = false
            self.message = "App updates are not configured for this build."
        } else if publicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            self.isConfigured = false
            self.message = "App updates need a Sparkle public signing key before release."
        } else {
            self.isConfigured = true
            self.message = nil
        }
    }
}
