import Foundation
import HavenCore

public enum ServiceUpdateDescriptorError: Error, LocalizedError, Equatable, Sendable {
    case missingArtifact(unitID: String)
    case unsupportedArtifactType(unitID: String, type: Artifact.ArtifactType)
    case missingAsset(unitID: String)

    public var errorDescription: String? {
        switch self {
        case .missingArtifact(let unitID):
            "No artifact metadata is available for \(unitID)"
        case .unsupportedArtifactType(let unitID, let type):
            "Updates for \(unitID) do not support artifact type \(type.rawValue)"
        case .missingAsset(let unitID):
            "No platform asset is available for \(unitID)"
        }
    }
}

public enum ServiceUpdateArtifactDescriptorFactory {
    public static func descriptor(
        for candidate: UpdateCandidate,
        installed: StoredArtifactInfo,
        runtimeUnit: RuntimeUnit,
        platform: PlatformInfo = .current
    ) throws -> ArtifactDescriptor {
        guard let artifact = runtimeUnit.artifact else {
            throw ServiceUpdateDescriptorError.missingArtifact(unitID: runtimeUnit.id)
        }
        guard artifact.type == .githubRelease else {
            throw ServiceUpdateDescriptorError.unsupportedArtifactType(
                unitID: runtimeUnit.id,
                type: artifact.type
            )
        }

        let assetFile = updatedAssetFile(
            installed.assetFile.isEmpty
                ? matchingAsset(in: artifact, platform: platform)?.file
                : installed.assetFile,
            currentVersion: candidate.currentVersion,
            latestVersion: candidate.latestVersion
        )

        guard let assetFile, !assetFile.isEmpty else {
            throw ServiceUpdateDescriptorError.missingAsset(unitID: runtimeUnit.id)
        }

        let updateArtifact = Artifact(
            type: .githubRelease,
            repo: candidate.repo,
            version: candidate.latestVersion,
            assets: [
                ArtifactAsset(
                    os: platform.os,
                    arch: platform.arch,
                    file: assetFile
                )
            ],
            archive: artifact.archive
        )

        var descriptor = try ArtifactResolver.resolve(
            artifact: updateArtifact,
            unitID: runtimeUnit.id,
            platform: platform
        )
        if let command = runtimeUnit.entrypoint?.command {
            descriptor = ArtifactDescriptor(
                unitID: descriptor.unitID,
                source: descriptor.source,
                format: descriptor.format,
                stripFirstDirectory: descriptor.stripFirstDirectory,
                entrypointCommand: command
            )
        }
        return descriptor
    }

    private static func matchingAsset(
        in artifact: Artifact,
        platform: PlatformInfo
    ) -> ArtifactAsset? {
        artifact.assets.first {
            $0.os == platform.os && $0.arch == platform.arch
        }
    }

    private static func updatedAssetFile(
        _ assetFile: String?,
        currentVersion: String,
        latestVersion: String
    ) -> String? {
        guard var assetFile else { return nil }

        let currentWithoutV = versionWithoutLeadingV(currentVersion)
        let latestWithoutV = versionWithoutLeadingV(latestVersion)

        assetFile = assetFile.replacingOccurrences(
            of: currentVersion,
            with: latestVersion
        )
        assetFile = assetFile.replacingOccurrences(
            of: currentWithoutV,
            with: latestWithoutV
        )

        return assetFile
    }

    private static func versionWithoutLeadingV(_ version: String) -> String {
        guard let first = version.first, first == "v" || first == "V" else {
            return version
        }
        return String(version.dropFirst())
    }
}

public struct ArtifactServiceUpdatePipeline: ServiceUpdateArtifactPipeline {
    public typealias DescriptorResolver = @Sendable (UpdateCandidate) throws -> ArtifactDescriptor

    private let installer: ArtifactInstaller
    private let descriptorResolver: DescriptorResolver

    public init(
        installer: ArtifactInstaller,
        descriptorResolver: @escaping DescriptorResolver
    ) {
        self.installer = installer
        self.descriptorResolver = descriptorResolver
    }

    public func download(_ candidate: UpdateCandidate) async throws -> PreparedServiceUpdate {
        let descriptor = try descriptorResolver(candidate)
        let stagingDirectory = try installer.prepareUpdate(descriptor: descriptor)
        return PreparedServiceUpdate(
            candidate: candidate,
            stagingDirectory: stagingDirectory
        )
    }

    public func validate(_ prepared: PreparedServiceUpdate) async throws {
        do {
            let descriptor = try descriptorResolver(prepared.candidate)
            guard let stagingDirectory = prepared.stagingDirectory else {
                throw ArtifactInstallerError.installFailed(
                    unitID: prepared.candidate.unitID,
                    detail: "Prepared update has no staging directory"
                )
            }
            try installer.validatePreparedUpdate(
                descriptor: descriptor,
                stagingDirectory: stagingDirectory
            )
        } catch {
            installer.discardPreparedUpdate(prepared)
            throw error
        }
    }

    public func promote(_ prepared: PreparedServiceUpdate) async throws -> ServiceUpdateRollbackToken {
        try installer.promotePreparedUpdate(prepared)
    }

    public func rollback(_ token: ServiceUpdateRollbackToken) async throws {
        try installer.rollbackPreparedUpdate(token)
    }

    public func finalize(_ token: ServiceUpdateRollbackToken) async throws {
        try installer.finalizePreparedUpdate(token)
    }
}
