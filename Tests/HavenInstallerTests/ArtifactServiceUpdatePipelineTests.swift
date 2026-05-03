import XCTest
import Foundation
import HavenCore
@testable import HavenInstaller

final class ArtifactServiceUpdatePipelineTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() {
        for root in tempRoots {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoots.removeAll()
        super.tearDown()
    }

    func testPromoteThenRollbackRestoresPreviousInstall() async throws {
        let root = try makeTempRoot()
        let cache = ArtifactCache(installedRoot: root.appendingPathComponent("Installed"))
        let installer = ArtifactInstaller(
            cache: cache,
            downloadsDirectory: root.appendingPathComponent("Downloads")
        )
        let candidate = makeCandidate()

        let finalDir = cache.installDirectory(for: candidate.unitID)
        try FileManager.default.createDirectory(at: finalDir, withIntermediateDirectories: true)
        try writeExecutable("old", to: finalDir.appendingPathComponent("runner"))

        let source = root.appendingPathComponent("runner")
        try writeExecutable("new", to: source)

        let pipeline = ArtifactServiceUpdatePipeline(installer: installer) { candidate in
            ArtifactDescriptor(
                unitID: candidate.unitID,
                source: .local(source),
                format: .executable,
                entrypointCommand: "runner"
            )
        }

        let prepared = try await pipeline.download(candidate)
        try await pipeline.validate(prepared)
        let token = try await pipeline.promote(prepared)

        XCTAssertEqual(
            try String(
                contentsOf: finalDir.appendingPathComponent("runner"),
                encoding: .utf8
            ),
            "new"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: token.previousInstallDirectory?.path ?? ""))

        try await pipeline.rollback(token)

        XCTAssertEqual(
            try String(
                contentsOf: finalDir.appendingPathComponent("runner"),
                encoding: .utf8
            ),
            "old"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: token.previousInstallDirectory?.path ?? ""))
    }

    func testFinalizeRemovesPreviousInstallAfterSuccessfulUpdate() async throws {
        let root = try makeTempRoot()
        let cache = ArtifactCache(installedRoot: root.appendingPathComponent("Installed"))
        let installer = ArtifactInstaller(
            cache: cache,
            downloadsDirectory: root.appendingPathComponent("Downloads")
        )
        let candidate = makeCandidate()

        let finalDir = cache.installDirectory(for: candidate.unitID)
        try FileManager.default.createDirectory(at: finalDir, withIntermediateDirectories: true)
        try writeExecutable("old", to: finalDir.appendingPathComponent("runner"))

        let source = root.appendingPathComponent("runner")
        try writeExecutable("new", to: source)

        let pipeline = ArtifactServiceUpdatePipeline(installer: installer) { candidate in
            ArtifactDescriptor(
                unitID: candidate.unitID,
                source: .local(source),
                format: .executable,
                entrypointCommand: "runner"
            )
        }

        let prepared = try await pipeline.download(candidate)
        try await pipeline.validate(prepared)
        let token = try await pipeline.promote(prepared)
        try await pipeline.finalize(token)

        XCTAssertEqual(
            try String(
                contentsOf: finalDir.appendingPathComponent("runner"),
                encoding: .utf8
            ),
            "new"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: token.previousInstallDirectory?.path ?? ""))
    }

    private func makeCandidate() -> UpdateCandidate {
        UpdateCandidate(
            unitID: "unit",
            repo: "owner/app",
            currentVersion: "v1.0.0",
            latestVersion: "v1.1.0"
        )
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-update-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        tempRoots.append(root)
        return root
    }

    private func writeExecutable(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}

final class StoredArtifactUpdateTransactionTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() {
        for root in tempRoots {
            try? FileManager.default.removeItem(at: root)
        }
        tempRoots.removeAll()
        super.tearDown()
    }

    func testCommitUpdatesArtifactVersionAndUpdatedAt() async throws {
        let root = try makeTempRoot()
        let paths = HavenPaths(base: root)
        let store = FileStateStore(paths: paths)
        try store.upsert(makeStoredService(paths: paths))

        let updatedAt = Date(timeIntervalSince1970: 2_000)
        let transaction = StoredArtifactUpdateTransaction(
            stateStore: store,
            now: { updatedAt }
        )

        _ = try await transaction.commit(
            makeCandidate(),
            replacementInstallDirectory: root.appendingPathComponent("Installed/unit")
        )

        let service = try XCTUnwrap(store.service(for: "capability"))
        XCTAssertEqual(service.artifactInfo.first?.version, "v1.1.0")
        XCTAssertEqual(service.updatedAt, updatedAt)
    }

    func testRollbackRestoresPreviousServiceMetadata() async throws {
        let root = try makeTempRoot()
        let paths = HavenPaths(base: root)
        let store = FileStateStore(paths: paths)
        let original = makeStoredService(paths: paths)
        try store.upsert(original)

        let transaction = StoredArtifactUpdateTransaction(stateStore: store)
        let token = try await transaction.commit(
            makeCandidate(),
            replacementInstallDirectory: root.appendingPathComponent("Installed/unit")
        )
        try await transaction.rollback(token)

        XCTAssertEqual(try store.service(for: "capability"), original)
    }

    private func makeCandidate() -> UpdateCandidate {
        UpdateCandidate(
            unitID: "unit",
            repo: "owner/app",
            currentVersion: "v1.0.0",
            latestVersion: "v1.1.0"
        )
    }

    private func makeStoredService(paths: HavenPaths) -> StoredServiceState {
        StoredServiceState(
            capability: "capability",
            bundleID: "bundle",
            installedAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_100),
            status: .running,
            resolvedSettings: [:],
            portAssignments: [],
            runtimeUnits: ["unit"],
            directoryLayout: paths.serviceLayout(for: "capability"),
            artifactInfo: [
                StoredArtifactInfo(
                    unitID: "unit",
                    repo: "owner/app",
                    version: "v1.0.0",
                    assetFile: "app_1.0.0_macos.tar.gz",
                    platform: "macos/arm64",
                    format: "tar.gz",
                    installDirectory: paths.installedDirectory
                        .appendingPathComponent("unit").path,
                    entrypoint: "runner"
                )
            ]
        )
    }

    private func makeTempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("haven-state-update-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        tempRoots.append(root)
        return root
    }
}
