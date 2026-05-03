import Foundation
import HavenInstaller

enum ServiceUpdateTone: Equatable {
    case neutral
    case available
    case progress
    case success
    case warning
    case failure
}

struct ServiceUpdatePresentation: Equatable {
    let title: String
    let detail: String?
    let systemImage: String
    let tone: ServiceUpdateTone
    let showsProgress: Bool
    let allowsPrimaryAction: Bool
    let allowsRetry: Bool

    static func make(for state: ServiceUpdateState) -> ServiceUpdatePresentation {
        switch state {
        case .idle:
            return ServiceUpdatePresentation(
                title: "Check for Updates",
                detail: nil,
                systemImage: "arrow.down.circle",
                tone: .neutral,
                showsProgress: false,
                allowsPrimaryAction: true,
                allowsRetry: false
            )
        case .checking:
            return ServiceUpdatePresentation(
                title: "Checking",
                detail: nil,
                systemImage: "arrow.trianglehead.2.clockwise",
                tone: .progress,
                showsProgress: true,
                allowsPrimaryAction: false,
                allowsRetry: false
            )
        case .upToDate(let version):
            return ServiceUpdatePresentation(
                title: "Up to Date",
                detail: version,
                systemImage: "checkmark.circle",
                tone: .success,
                showsProgress: false,
                allowsPrimaryAction: true,
                allowsRetry: false
            )
        case .updateAvailable(let candidate):
            return ServiceUpdatePresentation(
                title: "Update Available",
                detail: "\(candidate.currentVersion) → \(candidate.latestVersion)",
                systemImage: "arrow.down.circle.fill",
                tone: .available,
                showsProgress: false,
                allowsPrimaryAction: true,
                allowsRetry: false
            )
        case .downloading(let progress):
            let detail = progress.map { "\(Int($0 * 100))%" }
            return ServiceUpdatePresentation(
                title: "Downloading",
                detail: detail,
                systemImage: "arrow.down.circle",
                tone: .progress,
                showsProgress: true,
                allowsPrimaryAction: false,
                allowsRetry: false
            )
        case .validating:
            return progress("Validating", systemImage: "checkmark.shield")
        case .stopping:
            return progress("Stopping", systemImage: "stop.circle")
        case .replacing:
            return progress("Replacing", systemImage: "shippingbox")
        case .restarting:
            return progress("Restarting", systemImage: "arrow.clockwise")
        case .healthchecking:
            return progress("Healthchecking", systemImage: "heart")
        case .rollingBack:
            return ServiceUpdatePresentation(
                title: "Rolling Back",
                detail: nil,
                systemImage: "arrow.uturn.backward.circle",
                tone: .warning,
                showsProgress: true,
                allowsPrimaryAction: false,
                allowsRetry: false
            )
        case .rolledBack(let reason):
            return ServiceUpdatePresentation(
                title: "Rolled Back",
                detail: reason,
                systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                tone: .warning,
                showsProgress: false,
                allowsPrimaryAction: true,
                allowsRetry: true
            )
        case .completed(let candidate):
            return ServiceUpdatePresentation(
                title: "Updated",
                detail: candidate.latestVersion,
                systemImage: "checkmark.circle.fill",
                tone: .success,
                showsProgress: false,
                allowsPrimaryAction: true,
                allowsRetry: false
            )
        case .failed(let reason):
            return ServiceUpdatePresentation(
                title: "Update Failed",
                detail: reason,
                systemImage: "xmark.octagon",
                tone: .failure,
                showsProgress: false,
                allowsPrimaryAction: true,
                allowsRetry: true
            )
        }
    }

    private static func progress(
        _ title: String,
        systemImage: String
    ) -> ServiceUpdatePresentation {
        ServiceUpdatePresentation(
            title: title,
            detail: nil,
            systemImage: systemImage,
            tone: .progress,
            showsProgress: true,
            allowsPrimaryAction: false,
            allowsRetry: false
        )
    }
}
