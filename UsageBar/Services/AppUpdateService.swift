import Foundation

struct AppReleaseInfo {
    let version: String
    let releaseURL: URL
}

enum AppUpdateError: LocalizedError {
    case invalidEndpoint
    case invalidReleaseURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid release endpoint"
        case .invalidReleaseURL(let url):
            return "Invalid release URL: \(url)"
        }
    }
}

/// Fetches latest published release metadata for update checks.
final class AppUpdateService {
    private let networkClient: NetworkClient
    private let repository: String

    init(
        networkClient: NetworkClient = .shared,
        repository: String = "altansaid/macOs-app"
    ) {
        self.networkClient = networkClient
        self.repository = repository
    }

    func fetchLatestStableRelease() async throws -> AppReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw AppUpdateError.invalidEndpoint
        }

        let response: GitHubReleaseResponse = try await networkClient.get(
            url: url,
            headers: [
                "User-Agent": "QDock",
                "Accept": "application/vnd.github+json"
            ],
            responseType: GitHubReleaseResponse.self
        )

        guard let releaseURL = URL(string: response.htmlUrl) else {
            throw AppUpdateError.invalidReleaseURL(response.htmlUrl)
        }

        return AppReleaseInfo(
            version: Self.normalizeVersion(response.tagName),
            releaseURL: releaseURL
        )
    }

    private static func normalizeVersion(_ rawVersion: String) -> String {
        let trimmed = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let htmlUrl: String
}
