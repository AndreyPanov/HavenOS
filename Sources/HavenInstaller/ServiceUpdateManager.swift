import Foundation

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

public protocol ServiceUpdateArtifactPipeline: Sendable {
    func download(_ candidate: UpdateCandidate) async throws -> PreparedServiceUpdate
    func validate(_ prepared: PreparedServiceUpdate) async throws
    func promote(_ prepared: PreparedServiceUpdate) async throws -> ServiceUpdateRollbackToken
    func rollback(_ token: ServiceUpdateRollbackToken) async throws
}

public protocol ServiceUpdateRuntimeController: Sendable {
    func stop(unitID: String) async throws
    func start(unitID: String) async throws
    func healthcheck(unitID: String) async throws -> Bool
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

    public private(set) var state: ServiceUpdateState = .idle
    private var history: [ServiceUpdateState] = [.idle]

    public init(
        artifactPipeline: any ServiceUpdateArtifactPipeline,
        runtimeController: any ServiceUpdateRuntimeController
    ) {
        self.artifactPipeline = artifactPipeline
        self.runtimeController = runtimeController
    }

    @discardableResult
    public func apply(_ candidate: UpdateCandidate) async -> ServiceUpdateState {
        var didStop = false
        var didStartReplacement = false
        var rollbackToken: ServiceUpdateRollbackToken?

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

            let completed: ServiceUpdateState = .completed(candidate)
            transition(completed)
            return completed
        } catch {
            let rolledBack = await rollbackAfterFailure(
                candidate: candidate,
                didStop: didStop,
                didStartReplacement: didStartReplacement,
                rollbackToken: rollbackToken,
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
    }

    private func rollbackAfterFailure(
        candidate: UpdateCandidate,
        didStop: Bool,
        didStartReplacement: Bool,
        rollbackToken: ServiceUpdateRollbackToken?,
        originalError: Error
    ) async -> ServiceUpdateState {
        transition(.rollingBack)

        if didStartReplacement {
            try? await runtimeController.stop(unitID: candidate.unitID)
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
