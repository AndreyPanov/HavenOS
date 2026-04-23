import Foundation

/// Lightweight HTTP client for the Navidrome REST API.
///
/// All methods are async and throw on network or API errors.
/// This client is Sendable and can be called from any context.
struct NavidromeAPIClient: Sendable {
    let baseURL: URL

    init(port: Int) {
        self.baseURL = URL(string: "http://localhost:\(port)")!
    }

    // MARK: - Auth

    struct LoginResponse: Decodable, Sendable {
        let token: String
        let username: String
        let isAdmin: Bool?
    }

    /// Create the first admin account (only works on fresh Navidrome installs).
    func createAdmin(username: String, password: String) async throws -> LoginResponse {
        var request = URLRequest(url: baseURL.appending(path: "/auth/createAdmin"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": username, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode(LoginResponse.self, from: data)
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        var request = URLRequest(url: baseURL.appending(path: "/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": username, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode(LoginResponse.self, from: data)
    }

    // MARK: - Library Stats

    func getArtistCount(token: String) async throws -> Int {
        try await getCount(path: "/api/artist", token: token)
    }

    func getAlbumCount(token: String) async throws -> Int {
        try await getCount(path: "/api/album", token: token)
    }

    func getTrackCount(token: String) async throws -> Int {
        try await getCount(path: "/api/song", token: token)
    }

    /// Get count from X-Total-Count header using a minimal range request.
    private func getCount(path: String, token: String) async throws -> Int {
        var url = baseURL.appending(path: path)
        url.append(queryItems: [
            URLQueryItem(name: "_start", value: "0"),
            URLQueryItem(name: "_end", value: "0"),
        ])
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)

        if let http = response as? HTTPURLResponse,
           let countHeader = http.value(forHTTPHeaderField: "X-Total-Count"),
           let count = Int(countHeader) {
            return count
        }
        return 0
    }

    // MARK: - Scan

    func scanLibrary(token: String) async throws {
        var request = authorizedRequest(path: "/api/library/scan", token: token)
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
    }

    struct ScanStatus: Decodable, Sendable {
        let scanning: Bool
        let count: Int?
    }

    func getScanStatus(token: String) async throws -> ScanStatus {
        let request = authorizedRequest(path: "/api/library/scan", token: token)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode(ScanStatus.self, from: data)
    }

    // MARK: - Health

    func isHealthy() async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "/ping"))
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
            throw NavidromeAPIError.httpError(statusCode: http.statusCode, body: body)
        }
    }
}

enum NavidromeAPIError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            if let message = Self.extractMessage(from: body) { return message }
            if !body.isEmpty { return body }
            if code == 401 { return "Invalid credentials" }
            return "Server error (\(code))"
        }
    }

    private static func extractMessage(from body: String) -> String? {
        guard !body.isEmpty, let data = body.data(using: .utf8) else { return nil }

        if let message = try? JSONDecoder().decode(String.self, from: data) {
            return message
        }

        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error", "detail"] {
                if let msg = dict[key] as? String, !msg.isEmpty {
                    return msg
                }
            }
        }

        return nil
    }
}
