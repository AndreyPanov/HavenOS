import CryptoKit
import Foundation

/// Lightweight HTTP client for the Navidrome API.
///
/// Uses the REST API for auth and library info, and the Subsonic API for scan operations.
/// All methods are async and throw on network or API errors.
package struct NavidromeAPIClient: Sendable {
    package let baseURL: URL

    package init(port: Int) {
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

    // MARK: - Scan (Subsonic API)

    /// Trigger a library scan via the Subsonic `startScan` endpoint.
    func startScan(username: String, password: String) async throws {
        let request = subsonicRequest(path: "/rest/startScan", username: username, password: password)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        try checkSubsonicStatus(data)
    }

    struct ScanStatus: Decodable, Sendable {
        let scanning: Bool
        let count: Int
    }

    /// Get scan status via the Subsonic `getScanStatus` endpoint.
    func getScanStatus(username: String, password: String) async throws -> ScanStatus {
        let request = subsonicRequest(path: "/rest/getScanStatus", username: username, password: password)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        try checkSubsonicStatus(data)

        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sr = dict["subsonic-response"] as? [String: Any],
              let ss = sr["scanStatus"] as? [String: Any],
              let scanning = ss["scanning"] as? Bool else {
            throw NavidromeAPIError.httpError(statusCode: 0, body: "Invalid scan status response")
        }
        return ScanStatus(scanning: scanning, count: ss["count"] as? Int ?? 0)
    }

    // MARK: - Library Info

    struct LibraryInfo: Decodable, Sendable {
        let id: Int?
        let name: String?
        let path: String?
        let totalSongs: Int?
        let totalAlbums: Int?
        let totalArtists: Int?

        private enum CodingKeys: String, CodingKey {
            case id, name, path, totalSongs, totalAlbums, totalArtists
        }

        init(
            id: Int?,
            name: String?,
            path: String?,
            totalSongs: Int?,
            totalAlbums: Int?,
            totalArtists: Int?
        ) {
            self.id = id
            self.name = name
            self.path = path
            self.totalSongs = totalSongs
            self.totalAlbums = totalAlbums
            self.totalArtists = totalArtists
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let intID = try? c.decode(Int.self, forKey: .id) {
                id = intID
            } else if let stringID = try? c.decode(String.self, forKey: .id) {
                id = Int(stringID)
            } else {
                id = nil
            }
            name = try c.decodeIfPresent(String.self, forKey: .name)
            path = try c.decodeIfPresent(String.self, forKey: .path)
            totalSongs = try c.decodeIfPresent(Int.self, forKey: .totalSongs)
            totalAlbums = try c.decodeIfPresent(Int.self, forKey: .totalAlbums)
            totalArtists = try c.decodeIfPresent(Int.self, forKey: .totalArtists)
        }
    }

    /// Get all accessible libraries from `/api/library`.
    func getLibraries(token: String) async throws -> [LibraryInfo] {
        let request = authorizedRequest(path: "/api/library", token: token)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode([LibraryInfo].self, from: data)
    }

    /// Get aggregate library stats from `/api/library`.
    func getLibraryInfo(token: String) async throws -> LibraryInfo {
        let libraries = try await getLibraries(token: token)
        guard let first = libraries.first else {
            throw NavidromeAPIError.httpError(statusCode: 0, body: "No libraries found")
        }
        guard libraries.count > 1 else { return first }
        return LibraryInfo(
            id: nil,
            name: nil,
            path: nil,
            totalSongs: libraries.compactMap(\.totalSongs).reduce(0, +),
            totalAlbums: libraries.compactMap(\.totalAlbums).reduce(0, +),
            totalArtists: libraries.compactMap(\.totalArtists).reduce(0, +)
        )
    }

    /// Create an additional Navidrome library. Requires an admin token.
    func createLibrary(name: String, path: String, token: String) async throws {
        var request = authorizedRequest(path: "/api/library", token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": name,
            "path": path,
            "defaultNewUsers": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
    }

    /// Delete an additional Navidrome library by ID. Requires an admin token.
    func deleteLibrary(id: Int, token: String) async throws {
        var request = authorizedRequest(path: "/api/library/\(id)", token: token)
        request.httpMethod = "DELETE"
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
    }

    // MARK: - Health

    package func isHealthy() async -> Bool {
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
        request.setValue("Bearer \(token)", forHTTPHeaderField: "x-nd-authorization")
        return request
    }

    /// Build a Subsonic API request with salt+token auth.
    private func subsonicRequest(path: String, username: String, password: String) -> URLRequest {
        let salt = UUID().uuidString.prefix(8).lowercased()
        let tokenData = Insecure.MD5.hash(data: Data((password + salt).utf8))
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        var url = baseURL.appending(path: path)
        url.append(queryItems: [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "haven"),
            URLQueryItem(name: "f", value: "json"),
        ])
        return URLRequest(url: url)
    }

    /// Check Subsonic response for errors.
    private func checkSubsonicStatus(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sr = dict["subsonic-response"] as? [String: Any],
              let status = sr["status"] as? String else { return }
        if status == "failed" {
            let error = sr["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "Subsonic API error"
            throw NavidromeAPIError.httpError(statusCode: 0, body: message)
        }
    }

    private func checkHTTPStatus(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw NavidromeAPIError.httpError(statusCode: http.statusCode, body: body)
        }
    }
}

package enum NavidromeAPIError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String)

    package var errorDescription: String? {
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
