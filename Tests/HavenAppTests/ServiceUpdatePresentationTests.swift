import Testing
import HavenInstaller
@testable import HavenAppKit

@Suite("Service update presentation")
struct ServiceUpdatePresentationTests {
    @Test("update available state is actionable")
    func updateAvailableIsActionable() {
        let candidate = UpdateCandidate(
            unitID: "unit",
            repo: "owner/app",
            currentVersion: "v1.0.0",
            latestVersion: "v1.1.0"
        )

        let presentation = ServiceUpdatePresentation.make(
            for: .updateAvailable(candidate)
        )

        #expect(presentation.title == "Update Available")
        #expect(presentation.detail == "v1.0.0 → v1.1.0")
        #expect(presentation.tone == .available)
        #expect(presentation.allowsPrimaryAction)
        #expect(!presentation.showsProgress)
    }

    @Test("progress states show progress and disable actions")
    func progressStatesDisableActions() {
        for state in [
            ServiceUpdateState.downloading(progress: nil),
            .validating,
            .stopping,
            .replacing,
            .restarting,
            .healthchecking,
        ] {
            let presentation = ServiceUpdatePresentation.make(for: state)

            #expect(presentation.showsProgress)
            #expect(!presentation.allowsPrimaryAction)
            #expect(!presentation.allowsRetry)
        }
    }

    @Test("rollback state allows retry")
    func rollbackAllowsRetry() {
        let presentation = ServiceUpdatePresentation.make(
            for: .rolledBack(reason: "Healthcheck failed")
        )

        #expect(presentation.title == "Rolled Back")
        #expect(presentation.tone == .warning)
        #expect(presentation.allowsRetry)
        #expect(presentation.allowsPrimaryAction)
    }

    @Test("up to date state remains calm")
    func upToDateIsSuccessWithoutProgress() {
        let presentation = ServiceUpdatePresentation.make(
            for: .upToDate(version: "v1.0.0")
        )

        #expect(presentation.title == "Up to Date")
        #expect(presentation.detail == "v1.0.0")
        #expect(presentation.tone == .success)
        #expect(!presentation.showsProgress)
    }
}
