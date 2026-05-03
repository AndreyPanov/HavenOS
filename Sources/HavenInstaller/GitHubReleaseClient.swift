import Foundation

public struct GitHubRelease: Decodable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let prerelease: Bool
    public let draft: Bool
    public let htmlURL: URL?
    public let publishedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case prerelease
        case draft
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    public init(
        tagName: String,
        name: String? = nil,
        prerelease: Bool = false,
        draft: Bool = false,
        htmlURL: URL? = nil,
        publishedAt: Date? = nil
    ) {
        self.tagName = tagName
        self.name = name
        self.prerelease = prerelease
        self.draft = draft
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
    }
}

public struct GitHubReleaseClient: Sendable {
    private let session: URLSession
    private let apiBaseURL: URL

    public init(
        session: URLSession = .shared,
        apiBaseURL: URL = URL(string: "https://api.github.com")!
    ) {
        self.session = session
        self.apiBaseURL = apiBaseURL
    }

    public func latestStableRelease(repo: String) async throws -> GitHubRelease {
        let parts = repo.split(separator: "/")
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw UpdateError.invalidRepository(repo)
        }

        let url = apiBaseURL
            .appending(path: "repos")
            .appending(path: String(parts[0]))
            .appending(path: String(parts[1]))
            .appending(path: "releases")

        var request = URLRequest(url: url)
        request.setValue("HavenOS", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try checkHTTPStatus(response, data: data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let releases = try decoder.decode([GitHubRelease].self, from: data)
        guard let release = releases.first(where: { !$0.draft && !$0.prerelease }) else {
            throw UpdateError.noStableRelease(repo: repo)
        }
        return release
    }

    private func checkHTTPStatus(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw UpdateError.invalidResponse(statusCode: http.statusCode, body: body)
        }
    }
}
