import Foundation

/// Shared network client for making API requests
final class NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession
    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let formatterLock = NSLock()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// Perform a GET request with headers
    func get<T: Decodable>(
        url: URL,
        headers: [String: String] = [:],
        responseType: T.Type
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return try await execute(request, responseType: T.self)
    }

    /// Perform a POST request with form-urlencoded body
    func post<T: Decodable>(
        url: URL,
        headers: [String: String] = [:],
        formBody: [String: String],
        responseType: T.Type
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = formBody.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        return try await execute(request, responseType: T.self)
    }

    // MARK: - Private

    private func execute<T: Decodable>(_ request: URLRequest, responseType: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        do {
            return try Self.makeAPIDecoder().decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }

    /// Decoder used for all API responses: snake_case keys and ISO8601
    /// dates with or without fractional seconds. Exposed so tests decode
    /// fixtures exactly the way production does.
    static func makeAPIDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = Self.parseISO8601Date(str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(str)")
        }
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let date = isoFractionalFormatter.date(from: value) {
            return date
        }
        return isoFormatter.date(from: value)
    }
}

enum NetworkError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let body):
            return "HTTP \(statusCode): \(body.prefix(200))"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
