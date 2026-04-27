import Foundation

/// Lightweight HTTP client for the Jellyfin API.
///
/// Handles initial setup wizard, auth, library management, and health checks.
/// All methods are async and throw on network or API errors.
package struct JellyfinAPIClient: Sendable {
    package let baseURL: URL

    package init(port: Int) {
        self.baseURL = URL(string: "http://localhost:\(port)")!
    }

    // MARK: - Health

    package func isHealthy() async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "/System/Ping"))
        request.timeoutInterval = 5
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return false
        }
        return http.statusCode == 200
    }

    // MARK: - Setup Wizard

    /// Check if initial setup has been completed.
    func isSetupComplete() async throws -> Bool {
        let url = baseURL.appending(path: "/Startup/Configuration")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        // 404 means no startup wizard available (already completed)
        return http.statusCode == 404
    }

    /// Step 1: Set startup configuration (language, metadata language).
    func setStartupConfiguration() async throws {
        var request = URLRequest(url: baseURL.appending(path: "/Startup/Configuration"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let config: [String: Any] = [
            "UICulture": "en-US",
            "MetadataCountryCode": "US",
            "PreferredMetadataLanguage": "en",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: config)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data, allowNoContent: true)
    }

    /// Step 2a: Get the default startup user.
    /// Jellyfin must be polled until this returns a valid user —
    /// the user database may not be ready immediately after startup.
    struct SetupUserResponse: Decodable, Sendable {
        let Name: String?
        let Id: String?
    }

    func getStartupUser() async throws -> SetupUserResponse {
        let url = baseURL.appending(path: "/Startup/User")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode(SetupUserResponse.self, from: data)
    }

    /// Step 2b: Update the startup user with a name and password.
    func createSetupUser(username: String, password: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/Startup/User"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["Name": username, "Password": password])
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data, allowNoContent: true)
    }

    /// Step 3: Configure remote access settings during setup.
    func setRemoteAccess(enableRemote: Bool = true, enableUPnP: Bool = false) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/Startup/RemoteAccess"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let config = ["EnableRemoteAccess": enableRemote, "EnableAutomaticPortMapping": enableUPnP]
        request.httpBody = try JSONEncoder().encode(config)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data, allowNoContent: true)
    }

    /// Step 4: Complete the startup wizard.
    func completeSetup() async throws {
        var request = URLRequest(url: baseURL.appending(path: "/Startup/Complete"))
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data, allowNoContent: true)
    }

    // MARK: - Auth

    struct AuthResponse: Decodable, Sendable {
        let AccessToken: String
        let User: AuthUser

        struct AuthUser: Decodable, Sendable {
            let Name: String
            let Id: String
        }
    }

    /// Authenticate with username and password.
    func login(username: String, password: String) async throws -> AuthResponse {
        var request = URLRequest(url: baseURL.appending(path: "/Users/AuthenticateByName"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorizationHeader(token: nil), forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["Username": username, "Pw": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    // MARK: - Library Management

    /// Create a new library (virtual folder) with the given name, type, and paths.
    func createLibrary(name: String, collectionType: String, paths: [String], token: String) async throws {
        var url = baseURL.appending(path: "/Library/VirtualFolders")
        url.append(queryItems: [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "collectionType", value: collectionType),
            URLQueryItem(name: "refreshLibrary", value: "true"),
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        let body: [String: Any] = [
            "LibraryOptions": [
                "PathInfos": paths.map { ["Path": $0] },
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data, allowNoContent: true)
    }

    struct VirtualFolder: Decodable, Sendable {
        let Name: String
        let ItemId: String?
        let CollectionType: String?
        let Locations: [String]?
    }

    /// Remove a library by name.
    func removeLibrary(name: String, token: String) async throws {
        var url = baseURL.appending(path: "/Library/VirtualFolders")
        url.append(queryItems: [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "refreshLibrary", value: "false"),
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data, allowNoContent: true)
    }

    /// Get all configured libraries.
    func getLibraries(token: String) async throws -> [VirtualFolder] {
        var request = URLRequest(url: baseURL.appending(path: "/Library/VirtualFolders"))
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode([VirtualFolder].self, from: data)
    }

    /// Add a media path to an existing library.
    func addMediaPath(libraryName: String, path: String, token: String) async throws {
        var url = baseURL.appending(path: "/Library/VirtualFolders/Paths")
        url.append(queryItems: [URLQueryItem(name: "refreshLibrary", value: "true")])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        let body: [String: Any] = ["Name": libraryName, "Path": path]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data, allowNoContent: true)
    }

    /// Remove a media path from an existing library.
    func removeMediaPath(libraryName: String, path: String, token: String) async throws {
        var url = baseURL.appending(path: "/Library/VirtualFolders/Paths")
        url.append(queryItems: [
            URLQueryItem(name: "refreshLibrary", value: "true"),
            URLQueryItem(name: "name", value: libraryName),
            URLQueryItem(name: "path", value: path),
        ])
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data, allowNoContent: true)
    }

    // MARK: - Library Scan

    /// Trigger a full library refresh.
    func refreshLibrary(token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/Library/Refresh"))
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data, allowNoContent: true)
    }

    // MARK: - Item Counts

    struct ItemCounts: Decodable, Sendable {
        let MovieCount: Int
        let SeriesCount: Int
        let EpisodeCount: Int?
    }

    /// Get total item counts.
    func getItemCounts(token: String) async throws -> ItemCounts {
        var request = URLRequest(url: baseURL.appending(path: "/Items/Counts"))
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode(ItemCounts.self, from: data)
    }

    // MARK: - Scheduled Tasks (scan status)

    struct ScheduledTask: Decodable, Sendable {
        let Name: String?
        let State: String?
        let CurrentProgressPercentage: Double?
        let Key: String?
    }

    /// Get running scheduled tasks to check scan progress.
    func getScheduledTasks(token: String) async throws -> [ScheduledTask] {
        var request = URLRequest(url: baseURL.appending(path: "/ScheduledTasks"))
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode([ScheduledTask].self, from: data)
    }

    // MARK: - Helpers

    private func authorizationHeader(token: String?) -> String {
        var parts = [
            "MediaBrowser Client=\"Haven\"",
            "Device=\"Mac\"",
            "DeviceId=\"haven-mac\"",
            "Version=\"1.0.0\"",
        ]
        if let token {
            parts.append("Token=\"\(token)\"")
        }
        return parts.joined(separator: ", ")
    }

    private func checkHTTPStatus(_ response: URLResponse, data: Data?, allowNoContent: Bool = false) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if allowNoContent && http.statusCode == 204 { return }
        guard (200...299).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw JellyfinAPIError.httpError(statusCode: http.statusCode, body: body)
        }
    }
}

package enum JellyfinAPIError: Error, LocalizedError {
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
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "Message", "error", "detail"] {
                if let msg = dict[key] as? String, !msg.isEmpty {
                    return msg
                }
            }
        }
        return nil
    }
}
