import Foundation

/// Shared network client for making API requests
final class NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession

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

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
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
