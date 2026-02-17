import Foundation

struct AppReleaseInfo {
    let version: String
    let releaseURL: URL
}

enum AppUpdateError: LocalizedError {
    case invalidEndpoint
    case invalidReleaseURL(String)
    case npxNotFound
    case installerCommandFailed(status: Int32)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid release endpoint"
        case .invalidReleaseURL(let url):
            return "Invalid release URL: \(url)"
        case .npxNotFound:
            return "npx not found. Install Node.js to enable one-click updates."
        case .installerCommandFailed(let status):
            return "Automatic update failed (exit code \(status))."
        }
    }
}

/// Fetches latest published release metadata for update checks.
final class AppUpdateService {
    private let networkClient: NetworkClient
    private let repository: String
    private let installerPackage: String

    init(
        networkClient: NetworkClient = .shared,
        repository: String = "altansaid/macOs-app",
        installerPackage: String = "@altansaid/qdock-installer@latest"
    ) {
        self.networkClient = networkClient
        self.repository = repository
        self.installerPackage = installerPackage
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

    func installLatestReleaseWithNpx() async throws {
        guard let npxPath = resolveExecutable(named: "npx") else {
            throw AppUpdateError.npxNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: npxPath)
        process.arguments = ["--yes", installerPackage, "--no-launch"]
        process.environment = processEnvironment(npxPath: npxPath)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { runningProcess in
                continuation.resume(returning: runningProcess.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        guard status == 0 else {
            throw AppUpdateError.installerCommandFailed(status: status)
        }
    }

    private func processEnvironment(npxPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let npxDirectory = (npxPath as NSString).deletingLastPathComponent
        let existingPath = environment["PATH"] ?? ""
        let existingEntries = existingPath
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        let combinedEntries = [npxDirectory] + existingEntries + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        var uniqueEntries: [String] = []
        for entry in combinedEntries where !uniqueEntries.contains(entry) {
            uniqueEntries.append(entry)
        }

        environment["PATH"] = uniqueEntries.joined(separator: ":")
        return environment
    }

    private func resolveExecutable(named executable: String) -> String? {
        let fileManager = FileManager.default
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        let searchPaths = pathEntries + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        for directory in searchPaths {
            let candidate = "\(directory)/\(executable)"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let htmlUrl: String
}
