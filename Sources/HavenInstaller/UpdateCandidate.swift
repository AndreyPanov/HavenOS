import Foundation
import HavenCore

/// A concrete upstream version that may replace an installed artifact.
public struct UpdateCandidate: Equatable, Sendable {
    public let unitID: String
    public let repo: String
    public let currentVersion: String
    public let latestVersion: String
    public let releaseURL: URL?
    public let publishedAt: Date?

    public init(
        unitID: String,
        repo: String,
        currentVersion: String,
        latestVersion: String,
        releaseURL: URL? = nil,
        publishedAt: Date? = nil
    ) {
        self.unitID = unitID
        self.repo = repo
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releaseURL = releaseURL
        self.publishedAt = publishedAt
    }

    public var isNewerThanInstalled: Bool {
        VersionTag.isVersion(latestVersion, newerThan: currentVersion)
    }
}

/// User-visible state for update checks and update execution.
public enum ServiceUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(UpdateCandidate)
    case downloading(progress: Double?)
    case validating
    case stopping
    case replacing
    case restarting
    case healthchecking
    case rollingBack
    case rolledBack(reason: String)
    case completed(UpdateCandidate)
    case failed(reason: String)
}

public enum UpdateError: Error, LocalizedError, Equatable, Sendable {
    case invalidRepository(String)
    case noStableRelease(repo: String)
    case invalidResponse(statusCode: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidRepository(let repo):
            return "Invalid GitHub repository: \(repo)"
        case .noStableRelease(let repo):
            return "No stable release found for \(repo)"
        case .invalidResponse(let code, let body):
            return body.isEmpty ? "GitHub API error (\(code))" : body
        }
    }
}

public enum ServiceUpdateDiscovery {
    public static func candidate(
        for installed: StoredArtifactInfo,
        latest release: GitHubRelease
    ) -> UpdateCandidate {
        UpdateCandidate(
            unitID: installed.unitID,
            repo: installed.repo,
            currentVersion: installed.version,
            latestVersion: release.tagName,
            releaseURL: release.htmlURL,
            publishedAt: release.publishedAt
        )
    }

    public static func state(
        for installed: StoredArtifactInfo,
        latest release: GitHubRelease
    ) -> ServiceUpdateState {
        let candidate = candidate(for: installed, latest: release)
        return candidate.isNewerThanInstalled
            ? .updateAvailable(candidate)
            : .upToDate(version: installed.version)
    }
}

public enum VersionTag {
    public static func isVersion(_ candidate: String, newerThan installed: String) -> Bool {
        compare(candidate, installed) == .orderedDescending
    }

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(from: lhs)
        let right = components(from: rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }

        return .orderedSame
    }

    private static func components(from version: String) -> [Int] {
        var trimmed = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" {
            trimmed.removeFirst()
        }
        let withoutBuild = trimmed.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
        let releaseParts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        var components = (releaseParts.first.map(String.init) ?? "")
            .split { !$0.isNumber }
            .map { Int($0) ?? 0 }
        if releaseParts.count > 1,
           let suffix = releaseParts.last,
           suffix.allSatisfy({ $0.isNumber }),
           let numericSuffix = Int(suffix) {
            components.append(numericSuffix)
        }
        return components
    }
}
