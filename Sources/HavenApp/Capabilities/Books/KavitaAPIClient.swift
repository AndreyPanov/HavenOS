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

    /// Register the first admin account (only works on fresh Kavita installs).
    func register(username: String, password: String) async throws -> LoginResponse {
        var request = URLRequest(url: baseURL.appending(path: "/api/Account/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "username": username,
            "password": password,
            "email": ""
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        return try JSONDecoder().decode(LoginResponse.self, from: data)
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
        let libraryFileTypes: [Int]?
        let lastScanned: String?
    }

    func getLibraries(token: String) async throws -> [Library] {
        let request = authorizedRequest(path: "/api/Library/libraries", token: token)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
        // Kavita returns 204 No Content when no libraries exist
        if data.isEmpty { return [] }
        return try JSONDecoder().decode([Library].self, from: data)
    }

    /// Create a new library in Kavita.
    /// Type 2 = "Book" library.
    /// FileGroupTypes: 2=epub, 3=PDF, 4=images.
    /// Values 0, 1 (archive types) and 5 (other) crash the macOS scanner, so we skip them.
    func createLibrary(name: String, folders: [String], token: String) async throws {
        var request = authorizedRequest(path: "/api/Library/create", token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": name,
            "type": 2,
            "folders": folders,
            "folderWatching": true,
            "fileGroupTypes": [2, 3, 4],
            "excludePatterns": []
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
    }

    /// Update an existing library's file group types.
    /// Safe values on macOS: 2=epub, 3=PDF, 4=images. Values 0, 1, 5 crash the scanner.
    func updateLibraryFileTypes(library: Library, fileTypes: [Int], token: String) async throws {
        var request = authorizedRequest(path: "/api/Library/update", token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "id": library.id,
            "name": library.name,
            "type": library.type,
            "folders": library.folders,
            "folderWatching": true,
            "fileGroupTypes": fileTypes,
            "excludePatterns": []
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
    }

    /// Update an existing library's folders (changes where Kavita looks for books).
    func updateLibraryFolders(library: Library, folders: [String], token: String) async throws {
        var request = authorizedRequest(path: "/api/Library/update", token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "id": library.id,
            "name": library.name,
            "type": library.type,
            "folders": folders,
            "folderWatching": true,
            "fileGroupTypes": library.libraryFileTypes ?? [2, 3, 4],
            "excludePatterns": []
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)
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
        case .httpError(let code, let body):
            if let message = Self.extractMessage(from: body) { return message }
            if !body.isEmpty { return body }
            if code == 401 { return "Invalid credentials" }
            return "Server error (\(code))"
        }
    }

    /// Extract a human-readable message from Kavita's various JSON error formats.
    private static func extractMessage(from body: String) -> String? {
        guard !body.isEmpty, let data = body.data(using: .utf8) else { return nil }

        // Plain JSON string: "Some error message"
        if let message = try? JSONDecoder().decode(String.self, from: data) {
            return message
        }

        // ASP.NET validation: { "errors": { "field": ["msg", ...], ... } }
        // or Kavita object: { "message": "...", "title": "...", "detail": "..." }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // ASP.NET validation errors first (more specific than title):
            // { "errors": { "Password": ["Too short", ...] } }
            if let errors = dict["errors"] as? [String: Any] {
                var messages: [String] = []
                for (_, value) in errors {
                    if let arr = value as? [String] {
                        messages.append(contentsOf: arr)
                    } else if let str = value as? String {
                        messages.append(str)
                    }
                }
                if !messages.isEmpty {
                    return messages.joined(separator: ". ")
                }
            }

            // Fallback: { "message": "..." } or { "detail": "..." } or { "title": "..." }
            for key in ["message", "detail", "title"] {
                if let msg = dict[key] as? String, !msg.isEmpty {
                    return msg
                }
            }
        }

        // Array of strings: ["error1", "error2"]
        if let messages = try? JSONDecoder().decode([String].self, from: data), !messages.isEmpty {
            return messages.joined(separator: ". ")
        }

        return nil
    }
}
