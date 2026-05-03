import Foundation
import HavenCore

public struct PreparedServiceUpdate: Equatable, Sendable {
    public let candidate: UpdateCandidate
    public let stagingDirectory: URL?

    public init(candidate: UpdateCandidate, stagingDirectory: URL? = nil) {
        self.candidate = candidate
        self.stagingDirectory = stagingDirectory
    }
}

public struct ServiceUpdateRollbackToken: Equatable, Sendable {
    public let candidate: UpdateCandidate
    public let previousInstallDirectory: URL?
    public let replacementInstallDirectory: URL?

    public init(
        candidate: UpdateCandidate,
        previousInstallDirectory: URL? = nil,
        replacementInstallDirectory: URL? = nil
    ) {
        self.candidate = candidate
        self.previousInstallDirectory = previousInstallDirectory
        self.replacementInstallDirectory = replacementInstallDirectory
    }
}

public struct ServiceUpdateStateRollbackToken: Equatable, Sendable {
    public let previousService: StoredServiceState

    public init(previousService: StoredServiceState) {
        self.previousService = previousService
    }
}

public protocol ServiceUpdateArtifactPipeline: Sendable {
    func download(_ candidate: UpdateCandidate) async throws -> PreparedServiceUpdate
    func validate(_ prepared: PreparedServiceUpdate) async throws
    func promote(_ prepared: PreparedServiceUpdate) async throws -> ServiceUpdateRollbackToken
    func rollback(_ token: ServiceUpdateRollbackToken) async throws
    func finalize(_ token: ServiceUpdateRollbackToken) async throws
}

public extension ServiceUpdateArtifactPipeline {
    func finalize(_ token: ServiceUpdateRollbackToken) async throws {}
}

public protocol ServiceUpdateRuntimeController: Sendable {
    func stop(unitID: String) async throws
    func start(unitID: String) async throws
    func healthcheck(unitID: String) async throws -> Bool
}

public protocol ServiceUpdateStateTransaction: Sendable {
    func commit(
        _ candidate: UpdateCandidate,
        replacementInstallDirectory: URL?
    ) async throws -> ServiceUpdateStateRollbackToken
    func rollback(_ token: ServiceUpdateStateRollbackToken) async throws
}

public enum ServiceUpdateFlowError: Error, LocalizedError, Equatable, Sendable {
    case healthcheckFailed(unitID: String)

    public var errorDescription: String? {
        switch self {
        case .healthcheckFailed(let unitID):
            return "Healthcheck failed after updating \(unitID)"
        }
    }
}

/// Coordinates the safe update sequence:
/// Download -> Validate -> Stop -> Replace -> Restart -> Healthcheck -> Rollback on failure.
public actor ServiceUpdateManager {
    private let artifactPipeline: any ServiceUpdateArtifactPipeline
    private let runtimeController: any ServiceUpdateRuntimeController
    private let stateTransaction: (any ServiceUpdateStateTransaction)?
    private let onStateChange: (@Sendable (ServiceUpdateState) -> Void)?

    public private(set) var state: ServiceUpdateState = .idle
    private var history: [ServiceUpdateState] = [.idle]

    public init(
        artifactPipeline: any ServiceUpdateArtifactPipeline,
        runtimeController: any ServiceUpdateRuntimeController,
        stateTransaction: (any ServiceUpdateStateTransaction)? = nil,
        onStateChange: (@Sendable (ServiceUpdateState) -> Void)? = nil
    ) {
        self.artifactPipeline = artifactPipeline
        self.runtimeController = runtimeController
        self.stateTransaction = stateTransaction
        self.onStateChange = onStateChange
    }

    @discardableResult
    public func apply(_ candidate: UpdateCandidate) async -> ServiceUpdateState {
        var didStop = false
        var didStartReplacement = false
        var rollbackToken: ServiceUpdateRollbackToken?
        var stateRollbackToken: ServiceUpdateStateRollbackToken?

        do {
            transition(.downloading(progress: nil))
            let prepared = try await artifactPipeline.download(candidate)

            transition(.validating)
            try await artifactPipeline.validate(prepared)

            transition(.stopping)
            try await runtimeController.stop(unitID: candidate.unitID)
            didStop = true

            transition(.replacing)
            rollbackToken = try await artifactPipeline.promote(prepared)

            transition(.restarting)
            try await runtimeController.start(unitID: candidate.unitID)
            didStartReplacement = true

            transition(.healthchecking)
            guard try await runtimeController.healthcheck(unitID: candidate.unitID) else {
                throw ServiceUpdateFlowError.healthcheckFailed(unitID: candidate.unitID)
            }

            if let rollbackToken {
                stateRollbackToken = try await stateTransaction?.commit(
                    candidate,
                    replacementInstallDirectory: rollbackToken.replacementInstallDirectory
                )
                try? await artifactPipeline.finalize(rollbackToken)
            }

            let completed: ServiceUpdateState = .completed(candidate)
            transition(completed)
            return completed
        } catch {
            let rolledBack = await rollbackAfterFailure(
                candidate: candidate,
                didStop: didStop,
                didStartReplacement: didStartReplacement,
                rollbackToken: rollbackToken,
                stateRollbackToken: stateRollbackToken,
                originalError: error
            )
            transition(rolledBack)
            return rolledBack
        }
    }

    public func stateHistory() -> [ServiceUpdateState] {
        history
    }

    private func transition(_ next: ServiceUpdateState) {
        state = next
        history.append(next)
        onStateChange?(next)
    }

    private func rollbackAfterFailure(
        candidate: UpdateCandidate,
        didStop: Bool,
        didStartReplacement: Bool,
        rollbackToken: ServiceUpdateRollbackToken?,
        stateRollbackToken: ServiceUpdateStateRollbackToken?,
        originalError: Error
    ) async -> ServiceUpdateState {
        transition(.rollingBack)

        if didStartReplacement {
            try? await runtimeController.stop(unitID: candidate.unitID)
        }
        if let stateRollbackToken {
            try? await stateTransaction?.rollback(stateRollbackToken)
        }
        if let rollbackToken {
            try? await artifactPipeline.rollback(rollbackToken)
        }
        if didStop {
            try? await runtimeController.start(unitID: candidate.unitID)
        }

        return .rolledBack(reason: originalError.localizedDescription)
    }
}
