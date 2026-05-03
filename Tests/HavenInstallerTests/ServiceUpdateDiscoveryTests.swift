import XCTest
import Foundation
import HavenCore
@testable import HavenInstaller

final class VersionTagTests: XCTestCase {

    func testComparesNewerSemanticVersion() {
        XCTAssertTrue(VersionTag.isVersion("v1.2.4", newerThan: "v1.2.3"))
        XCTAssertTrue(VersionTag.isVersion("1.10.0", newerThan: "1.9.9"))
        XCTAssertTrue(VersionTag.isVersion("v2.0.0", newerThan: "v1.99.99"))
    }

    func testDoesNotTreatSameOrOlderAsNewer() {
        XCTAssertFalse(VersionTag.isVersion("v1.2.3", newerThan: "1.2.3"))
        XCTAssertFalse(VersionTag.isVersion("v1.2.2", newerThan: "v1.2.3"))
        XCTAssertFalse(VersionTag.isVersion("v1.2.0", newerThan: "v1.2"))
    }

    func testIgnoresPrereleaseSuffixForBaseComparison() {
        XCTAssertFalse(VersionTag.isVersion("v1.2.3-beta.1", newerThan: "v1.2.3"))
        XCTAssertTrue(VersionTag.isVersion("v1.2.4-beta.1", newerThan: "v1.2.3"))
    }
}

final class ServiceUpdateDiscoveryTests: XCTestCase {

    func testCreatesUpdateAvailableStateForNewerRelease() {
        let installed = StoredArtifactInfo(
            unitID: "unit",
            repo: "owner/app",
            version: "v1.0.0",
            assetFile: "app.zip",
            platform: "macos/arm64",
            format: "zip",
            installDirectory: "/tmp/app"
        )
        let release = GitHubRelease(tagName: "v1.1.0")

        let state = ServiceUpdateDiscovery.state(for: installed, latest: release)

        guard case .updateAvailable(let candidate) = state else {
            return XCTFail("Expected updateAvailable")
        }
        XCTAssertEqual(candidate.unitID, "unit")
        XCTAssertEqual(candidate.repo, "owner/app")
        XCTAssertEqual(candidate.currentVersion, "v1.0.0")
        XCTAssertEqual(candidate.latestVersion, "v1.1.0")
    }

    func testCreatesUpToDateStateForSameRelease() {
        let installed = StoredArtifactInfo(
            unitID: "unit",
            repo: "owner/app",
            version: "v1.0.0",
            assetFile: "app.zip",
            platform: "macos/arm64",
            format: "zip",
            installDirectory: "/tmp/app"
        )
        let release = GitHubRelease(tagName: "1.0.0")

        XCTAssertEqual(
            ServiceUpdateDiscovery.state(for: installed, latest: release),
            .upToDate(version: "v1.0.0")
        )
    }
}

final class GitHubReleaseTests: XCTestCase {

    func testDecodesGitHubReleasePayload() throws {
        let json = """
        {
          "tag_name": "v1.2.3",
          "name": "Release 1.2.3",
          "draft": false,
          "prerelease": false,
          "html_url": "https://github.com/owner/app/releases/tag/v1.2.3",
          "published_at": "2026-05-01T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: json)

        XCTAssertEqual(release.tagName, "v1.2.3")
        XCTAssertEqual(release.name, "Release 1.2.3")
        XCTAssertFalse(release.draft)
        XCTAssertFalse(release.prerelease)
        XCTAssertEqual(release.htmlURL?.absoluteString, "https://github.com/owner/app/releases/tag/v1.2.3")
        XCTAssertNotNil(release.publishedAt)
    }
}
