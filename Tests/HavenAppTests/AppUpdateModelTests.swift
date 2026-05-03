import Foundation
import Testing
@testable import HavenAppKit

private final class AppUpdateModelTestsBundleMarker {}

@Suite("App update model")
@MainActor
struct AppUpdateModelTests {
    @Test("missing Sparkle release config disables update checks")
    func missingSparkleReleaseConfigDisablesUpdateChecks() {
        let model = AppUpdateModel(bundle: Bundle(for: AppUpdateModelTestsBundleMarker.self))

        #expect(!model.isConfigured)
        #expect(!model.canCheckForUpdates)
        #expect(model.configurationMessage == "App updates are not configured for this build.")
    }
}
