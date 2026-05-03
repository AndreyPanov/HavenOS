import Foundation
import HavenCore

public enum ServiceUpdateMetadataError: Error, LocalizedError, Equatable, Sendable {
    case artifactNotFound(unitID: String)

    public var errorDescription: String? {
        switch self {
        case .artifactNotFound(let unitID):
            return "No installed artifact metadata found for \(unitID)"
        }
    }
}

public struct StoredArtifactUpdateTransaction: ServiceUpdateStateTransaction {
    private let stateStore: any StateStore
    private let now: @Sendable () -> Date

    public init(
        stateStore: any StateStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.stateStore = stateStore
        self.now = now
    }

    public func commit(
        _ candidate: UpdateCandidate,
        replacementInstallDirectory: URL?
    ) async throws -> ServiceUpdateStateRollbackToken {
        var state = try stateStore.load()

        guard let serviceKey = state.services.first(where: { _, service in
            service.artifactInfo.contains { $0.unitID == candidate.unitID }
        })?.key,
              let service = state.services[serviceKey],
              let artifactIndex = service.artifactInfo.firstIndex(where: {
                  $0.unitID == candidate.unitID
              })
        else {
            throw ServiceUpdateMetadataError.artifactNotFound(
                unitID: candidate.unitID
            )
        }

        let previousService = service
        let oldArtifact = service.artifactInfo[artifactIndex]
        var updatedArtifacts = service.artifactInfo
        updatedArtifacts[artifactIndex] = StoredArtifactInfo(
            unitID: oldArtifact.unitID,
            repo: oldArtifact.repo,
            version: candidate.latestVersion,
            assetFile: oldArtifact.assetFile,
            platform: oldArtifact.platform,
            format: oldArtifact.format,
            installDirectory: replacementInstallDirectory?.path
                ?? oldArtifact.installDirectory,
            entrypoint: oldArtifact.entrypoint
        )

        let updatedService = StoredServiceState(
            capability: service.capability,
            bundleID: service.bundleID,
            installedAt: service.installedAt,
            updatedAt: now(),
            status: service.status,
            resolvedSettings: service.resolvedSettings,
            portAssignments: service.portAssignments,
            runtimeUnits: service.runtimeUnits,
            directoryLayout: service.directoryLayout,
            artifactInfo: updatedArtifacts,
            pythonInfo: service.pythonInfo,
            onboarding: service.onboarding,
            readinessProbes: service.readinessProbes
        )

        state.services[serviceKey] = updatedService
        try stateStore.save(state)

        return ServiceUpdateStateRollbackToken(previousService: previousService)
    }

    public func rollback(_ token: ServiceUpdateStateRollbackToken) async throws {
        try stateStore.upsert(token.previousService)
    }
}
