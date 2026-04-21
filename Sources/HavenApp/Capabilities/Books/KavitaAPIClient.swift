import Foundation

/// Lightweight HTTP client for the Kavita REST API.
///
/// All methods are async and throw on network or API errors.
/// This client is Sendable and can be called from any context.
struct KavitaAPIClient: Sendable {
    let baseURL: URL

    init(port: Int) {
        self.baseURL = URL(string: "http://localhost:\(port)")!
    }

    // MARK: - Auth

    struct LoginResponse: Decodable, Sendable {
        let token: String
        let username: String
        let apiKey: String?
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        var request = URLRequest(url: baseURL.appending(path: "/api/Account/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": username, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode(LoginResponse.self, from: data)
    }

    // MARK: - Libraries

    struct Library: Decodable, Sendable {
        let id: Int
        let name: String
        let folders: [String]
        let type: Int
    }

    func getLibraries(token: String) async throws -> [Library] {
        let request = authorizedRequest(path: "/api/Library", token: token)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode([Library].self, from: data)
    }

    func scanLibrary(id: Int, token: String) async throws {
        var request = authorizedRequest(path: "/api/Library/scan", token: token)
        request.httpMethod = "POST"
        request.url = request.url?.appending(queryItems: [URLQueryItem(name: "libraryId", value: "\(id)")])
        let (_, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: nil)
    }

    func scanAllLibraries(token: String) async throws {
        var request = authorizedRequest(path: "/api/Library/scan-all", token: token)
        request.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: nil)
    }

    // MARK: - Series (for book count)

    struct SeriesResponse: Decodable, Sendable {
        // Kavita wraps paginated results; we only need total count
        let totalItems: Int?

        enum CodingKeys: String, CodingKey {
            case totalItems
        }

        init(from decoder: Decoder) throws {
            // Kavita returns pagination info in response headers,
            // so we decode the array and count items as fallback
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            totalItems = try container?.decodeIfPresent(Int.self, forKey: .totalItems)
        }
    }

    struct SeriesItem: Decodable, Sendable {
        let id: Int
        let name: String
        let pages: Int?
    }

    func getSeriesCount(token: String) async throws -> Int {
        // Use the series endpoint with page size 1 to get total from pagination header
        var request = authorizedRequest(path: "/api/Series/v2", token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["statements": [], "combination": 1, "limitTo": 0, "sortOptions": ["sortField": 1, "isAscending": true]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)

        // Kavita returns pagination in the "Pagination" header
        if let httpResponse = response as? HTTPURLResponse,
           let paginationHeader = httpResponse.value(forHTTPHeaderField: "Pagination"),
           let paginationData = paginationHeader.data(using: .utf8) {
            struct PaginationInfo: Decodable { let totalItems: Int }
            if let info = try? JSONDecoder().decode(PaginationInfo.self, from: paginationData) {
                return info.totalItems
            }
        }

        // Fallback: count the decoded array
        let items = try? JSONDecoder().decode([SeriesItem].self, from: data)
        return items?.count ?? 0
    }

    // MARK: - Health

    func isHealthy() async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "/api/health"))
        request.timeoutInterval = 5
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return false
        }
        return http.statusCode == 200
    }

    // MARK: - Helpers

    private func authorizedRequest(path: String, token: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func checkHTTPStatus(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw KavitaAPIError.httpError(statusCode: http.statusCode, body: body)
        }
    }
}

enum KavitaAPIError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, _):
            if code == 401 { return "Invalid credentials" }
            return "Server error (\(code))"
        }
    }
}
