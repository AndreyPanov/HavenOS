import XCTest
import Foundation
import HavenCore
@testable import HavenInstaller

// MARK: - ArtifactResolver Tests

final class ArtifactResolverTests: XCTestCase {

    // MARK: - Helpers

    private func makeArtifact(
        type: Artifact.ArtifactType = .githubRelease,
        repo: String = "owner/hello-service",
        version: String = "v1.0.0",
        assets: [ArtifactAsset] = [
            ArtifactAsset(os: "macos", arch: "arm64", file: "hello-service-macos-arm64.zip"),
            ArtifactAsset(os: "macos", arch: "x86_64", file: "hello-service-macos-x86_64.tar.gz"),
        ],
        archive: ArtifactArchive? = nil
    ) -> Artifact {
        Artifact(
            type: type,
            repo: repo,
            version: version,
            assets: assets,
            archive: archive
        )
    }

    // MARK: - Happy Path

    func testResolveArm64Asset() throws {
        let artifact = makeArtifact()
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        let descriptor = try ArtifactResolver.resolve(
            artifact: artifact,
            unitID: "haven.unit.hello",
            platform: platform
        )

        XCTAssertEqual(descriptor.unitID, "haven.unit.hello")
        XCTAssertEqual(
            descriptor.source,
            .remote(URL(string: "https://github.com/owner/hello-service/releases/download/v1.0.0/hello-service-macos-arm64.zip")!)
        )
        XCTAssertEqual(descriptor.format, .zip)
        XCTAssertFalse(descriptor.stripFirstDirectory)
    }

    func testResolveX86Asset() throws {
        let artifact = makeArtifact()
        let platform = PlatformInfo(os: "macos", arch: "x86_64")

        let descriptor = try ArtifactResolver.resolve(
            artifact: artifact,
            unitID: "haven.unit.hello",
            platform: platform
        )

        XCTAssertEqual(
            descriptor.source,
            .remote(URL(string: "https://github.com/owner/hello-service/releases/download/v1.0.0/hello-service-macos-x86_64.tar.gz")!)
        )
        XCTAssertEqual(descriptor.format, .tarGz)
    }

    func testResolveDarwinAmd64Aliases() throws {
        let artifact = makeArtifact(
            assets: [
                ArtifactAsset(os: "darwin", arch: "amd64", file: "app-darwin-amd64.tar.gz")
            ]
        )
        let platform = PlatformInfo(os: "macos", arch: "x86_64")

        let descriptor = try ArtifactResolver.resolve(
            artifact: artifact,
            unitID: "u.1",
            platform: platform
        )

        XCTAssertEqual(
            descriptor.source,
            .remote(URL(string: "https://github.com/owner/hello-service/releases/download/v1.0.0/app-darwin-amd64.tar.gz")!)
        )
        XCTAssertEqual(descriptor.format, .tarGz)
    }

    // MARK: - Format Detection

    func testExplicitArchiveFormatOverridesFilename() throws {
        let artifact = makeArtifact(
            assets: [ArtifactAsset(os: "macos", arch: "arm64", file: "app-arm64.bin")],
            archive: ArtifactArchive(format: "zip")
        )
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        let descriptor = try ArtifactResolver.resolve(
            artifact: artifact,
            unitID: "u.1",
            platform: platform
        )

        XCTAssertEqual(descriptor.format, .zip)
    }

    func testExplicitTarGzFormat() throws {
        let artifact = makeArtifact(
            assets: [ArtifactAsset(os: "macos", arch: "arm64", file: "app")],
            archive: ArtifactArchive(format: "tar.gz")
        )
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        let descriptor = try ArtifactResolver.resolve(
            artifact: artifact,
            unitID: "u.1",
            platform: platform
        )

        XCTAssertEqual(descriptor.format, .tarGz)
    }

    func testExplicitTgzFormat() throws {
        let artifact = makeArtifact(
            assets: [ArtifactAsset(os: "macos", arch: "arm64", file: "app")],
            archive: ArtifactArchive(format: "tgz")
        )
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        let descriptor = try ArtifactResolver.resolve(
            artifact: artifact,
            unitID: "u.1",
            platform: platform
        )

        XCTAssertEqual(descriptor.format, .tarGz)
    }

    func testFallbackToFilenameDetection() throws {
        let artifact = makeArtifact(
            assets: [ArtifactAsset(os: "macos", arch: "arm64", file: "app.tar.gz")]
        )
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        let descriptor = try ArtifactResolver.resolve(
            artifact: artifact,
            unitID: "u.1",
            platform: platform
        )

        XCTAssertEqual(descriptor.format, .tarGz)
    }

    func testNoArchiveNoExtensionDefaultsToExecutable() throws {
        let artifact = makeArtifact(
            assets: [ArtifactAsset(os: "macos", arch: "arm64", file: "hello-service")]
        )
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        let descriptor = try ArtifactResolver.resolve(
            artifact: artifact,
            unitID: "u.1",
            platform: platform
        )

        XCTAssertEqual(descriptor.format, .executable)
    }

    // MARK: - stripFirstDirectory

    func testStripFirstDirectoryPropagated() throws {
        let artifact = makeArtifact(
            archive: ArtifactArchive(format: "zip", stripFirstDirectory: true)
        )
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        let descriptor = try ArtifactResolver.resolve(
            artifact: artifact,
            unitID: "u.1",
            platform: platform
        )

        XCTAssertTrue(descriptor.stripFirstDirectory)
    }

    func testStripFirstDirectoryDefaultsFalse() throws {
        let artifact = makeArtifact(
            archive: ArtifactArchive(format: "zip")
        )
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        let descriptor = try ArtifactResolver.resolve(
            artifact: artifact,
            unitID: "u.1",
            platform: platform
        )

        XCTAssertFalse(descriptor.stripFirstDirectory)
    }

    // MARK: - URL Construction

    func testGitHubURLConstruction() throws {
        let artifact = makeArtifact(
            repo: "myorg/myapp",
            version: "v2.3.1",
            assets: [ArtifactAsset(os: "macos", arch: "arm64", file: "myapp-darwin-arm64.zip")]
        )
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        let descriptor = try ArtifactResolver.resolve(
            artifact: artifact,
            unitID: "u.1",
            platform: platform
        )

        if case .remote(let url) = descriptor.source {
            XCTAssertEqual(
                url.absoluteString,
                "https://github.com/myorg/myapp/releases/download/v2.3.1/myapp-darwin-arm64.zip"
            )
        } else {
            XCTFail("Expected remote source")
        }
    }

    // MARK: - Error Cases

    func testNoMatchingAsset() {
        let artifact = makeArtifact(
            assets: [ArtifactAsset(os: "linux", arch: "arm64", file: "app-linux.tar.gz")]
        )
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        XCTAssertThrowsError(
            try ArtifactResolver.resolve(
                artifact: artifact,
                unitID: "u.1",
                platform: platform
            )
        ) { error in
            guard case .noMatchingAsset(let unitID, let os, let arch) = error as? ArtifactResolverError else {
                XCTFail("Expected noMatchingAsset, got \(error)")
                return
            }
            XCTAssertEqual(unitID, "u.1")
            XCTAssertEqual(os, "macos")
            XCTAssertEqual(arch, "arm64")
        }
    }

    func testInvalidRepositoryFormat() {
        let artifact = makeArtifact(repo: "just-a-name")
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        XCTAssertThrowsError(
            try ArtifactResolver.resolve(
                artifact: artifact,
                unitID: "u.1",
                platform: platform
            )
        ) { error in
            guard case .invalidRepository(let unitID, let repo) = error as? ArtifactResolverError else {
                XCTFail("Expected invalidRepository, got \(error)")
                return
            }
            XCTAssertEqual(unitID, "u.1")
            XCTAssertEqual(repo, "just-a-name")
        }
    }

    func testEmptyRepoSegment() {
        let artifact = makeArtifact(repo: "/repo")
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        XCTAssertThrowsError(
            try ArtifactResolver.resolve(
                artifact: artifact,
                unitID: "u.1",
                platform: platform
            )
        ) { error in
            guard case .invalidRepository = error as? ArtifactResolverError else {
                XCTFail("Expected invalidRepository, got \(error)")
                return
            }
        }
    }

    func testEmptyAssets() {
        let artifact = makeArtifact(assets: [])
        let platform = PlatformInfo(os: "macos", arch: "arm64")

        XCTAssertThrowsError(
            try ArtifactResolver.resolve(
                artifact: artifact,
                unitID: "u.1",
                platform: platform
            )
        ) { error in
            guard case .noMatchingAsset = error as? ArtifactResolverError else {
                XCTFail("Expected noMatchingAsset, got \(error)")
                return
            }
        }
    }
}

// MARK: - PlatformInfo Tests

final class PlatformInfoTests: XCTestCase {

    func testCurrentPlatformIsMacOS() {
        let info = PlatformInfo.current
        XCTAssertEqual(info.os, "macos")
    }

    func testCurrentArchIsKnown() {
        let info = PlatformInfo.current
        XCTAssertTrue(
            info.arch == "arm64" || info.arch == "x86_64",
            "Expected arm64 or x86_64, got \(info.arch)"
        )
    }

    func testEquality() {
        let a = PlatformInfo(os: "macos", arch: "arm64")
        let b = PlatformInfo(os: "macos", arch: "arm64")
        XCTAssertEqual(a, b)
    }

    func testInequality() {
        let a = PlatformInfo(os: "macos", arch: "arm64")
        let b = PlatformInfo(os: "macos", arch: "x86_64")
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - ArtifactResolverError Tests

final class ArtifactResolverErrorTests: XCTestCase {

    func testEquality() {
        let a = ArtifactResolverError.noMatchingAsset(unitID: "u", os: "macos", arch: "arm64")
        let b = ArtifactResolverError.noMatchingAsset(unitID: "u", os: "macos", arch: "arm64")
        XCTAssertEqual(a, b)
    }

    func testInequality() {
        let a = ArtifactResolverError.noMatchingAsset(unitID: "u", os: "macos", arch: "arm64")
        let b = ArtifactResolverError.invalidRepository(unitID: "u", repo: "bad")
        XCTAssertNotEqual(a, b)
    }

    func testErrorDescriptions() {
        let errors: [ArtifactResolverError] = [
            .noMatchingAsset(unitID: "u", os: "macos", arch: "arm64"),
            .invalidRepository(unitID: "u", repo: "bad"),
            .unsupportedArtifactType(unitID: "u", type: "docker"),
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
    }
}
