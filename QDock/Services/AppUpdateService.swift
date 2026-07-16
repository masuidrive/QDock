import CryptoKit
import Foundation

struct AppReleaseAsset {
    let name: String
    let downloadURL: URL
}

struct AppReleaseInfo {
    let version: String
    let releaseURL: URL
    let dmg: AppReleaseAsset?
    let checksums: AppReleaseAsset?
}

enum AppUpdateError: LocalizedError {
    case invalidEndpoint
    case invalidReleaseURL(String)
    case missingDMGAsset
    case missingChecksumsAsset
    case downloadFailed(assetName: String, statusCode: Int)
    case checksumEntryMissing(String)
    case checksumMismatch
    case mountFailed
    case appBundleNotFoundInDMG
    case commandFailed(command: String, status: Int32)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid release endpoint"
        case .invalidReleaseURL(let url):
            return "Invalid release URL: \(url)"
        case .missingDMGAsset:
            return "No DMG found in the latest release."
        case .missingChecksumsAsset:
            return "No checksums.txt found in the latest release."
        case .downloadFailed(let assetName, let statusCode):
            return "Download of \(assetName) failed (HTTP \(statusCode))."
        case .checksumEntryMissing(let assetName):
            return "No checksum entry for \(assetName) in checksums.txt."
        case .checksumMismatch:
            return "Checksum verification failed for the downloaded update."
        case .mountFailed:
            return "Could not mount the downloaded update image."
        case .appBundleNotFoundInDMG:
            return "No app bundle found inside the downloaded update."
        case .commandFailed(let command, let status):
            return "\(command) failed (exit code \(status))."
        }
    }
}

/// Fetches latest published release metadata and installs updates by
/// downloading the release DMG directly from GitHub - no npm/npx involved.
final class AppUpdateService {
    private let networkClient: NetworkClient
    private let repository: String
    private let session: URLSession

    init(
        networkClient: NetworkClient = .shared,
        repository: String = "altansaid/QDock"
    ) {
        self.networkClient = networkClient
        self.repository = repository

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Release metadata

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

        let assets = (response.assets ?? []).compactMap { asset -> AppReleaseAsset? in
            guard let url = URL(string: asset.browserDownloadUrl) else { return nil }
            return AppReleaseAsset(name: asset.name, downloadURL: url)
        }

        return AppReleaseInfo(
            version: Self.normalizeVersion(response.tagName),
            releaseURL: releaseURL,
            dmg: assets.first { $0.name.lowercased().hasSuffix(".dmg") },
            checksums: assets.first { $0.name.lowercased() == "checksums.txt" }
        )
    }

    static func normalizeVersion(_ rawVersion: String) -> String {
        let trimmed = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    // MARK: - Install

    /// Downloads the release DMG, verifies its checksum, and replaces the
    /// installed app bundle. Returns the path the app was installed to.
    /// `installDirectory` defaults to wherever the running bundle lives
    /// (falling back to /Applications), and is overridable for tests.
    @discardableResult
    func installRelease(_ release: AppReleaseInfo, into installDirectory: URL? = nil) async throws -> URL {
        guard let dmg = release.dmg else { throw AppUpdateError.missingDMGAsset }
        guard let checksums = release.checksums else { throw AppUpdateError.missingChecksumsAsset }

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("qdock-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let dmgPath = tempDir.appendingPathComponent(dmg.name)
        try await download(dmg, to: dmgPath)

        let checksumsPath = tempDir.appendingPathComponent(checksums.name)
        try await download(checksums, to: checksumsPath)
        try Self.verifyChecksum(of: dmgPath, against: checksumsPath)

        let mountPoint = try await attachDMG(at: dmgPath)
        defer { detachDMG(at: mountPoint) }

        let appSource = try Self.locateAppBundle(inVolume: mountPoint)
        let targetDirectory = installDirectory ?? Self.defaultInstallDirectory()
        return try await copyApp(from: appSource, intoDirectory: targetDirectory)
    }

    // MARK: - Download & verify

    private func download(_ asset: AppReleaseAsset, to destination: URL) async throws {
        var request = URLRequest(url: asset.downloadURL)
        request.setValue("QDock", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let (temporaryURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AppUpdateError.downloadFailed(assetName: asset.name, statusCode: status)
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    static func verifyChecksum(of artifactPath: URL, against checksumsPath: URL) throws {
        let checksumsContent = try String(contentsOf: checksumsPath, encoding: .utf8)
        let artifactName = artifactPath.lastPathComponent

        guard let expected = expectedChecksum(in: checksumsContent, for: artifactName) else {
            throw AppUpdateError.checksumEntryMissing(artifactName)
        }

        let actual = try sha256Hex(of: artifactPath)
        guard expected == actual else {
            throw AppUpdateError.checksumMismatch
        }
    }

    /// Parses standard `shasum -a 256` output: `<hex>  <name>` or `<hex> *<name>`.
    static func expectedChecksum(in checksumsContent: String, for artifactName: String) -> String? {
        checksumsContent
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasSuffix("  \(artifactName)") || $0.hasSuffix(" *\(artifactName)") }?
            .split(separator: " ", maxSplits: 1)
            .first
            .map { $0.lowercased() }
    }

    private static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return SHA256.digest(hasher.finalize())
    }

    // MARK: - DMG handling

    private func attachDMG(at dmgPath: URL) async throws -> String {
        let output = try await runCommand(
            "/usr/bin/hdiutil",
            arguments: ["attach", "-nobrowse", "-readonly", dmgPath.path]
        )
        guard let mountPoint = Self.parseMountPoint(from: output) else {
            throw AppUpdateError.mountFailed
        }
        return mountPoint
    }

    private func detachDMG(at mountPoint: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-quiet"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    static func parseMountPoint(from attachOutput: String) -> String? {
        for line in attachOutput.split(whereSeparator: \.isNewline) {
            guard line.contains("/Volumes/") else { continue }
            let fields = line.split(separator: "\t").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if let mountPoint = fields.last(where: { $0.hasPrefix("/Volumes/") }) {
                return mountPoint
            }
        }
        return nil
    }

    static func locateAppBundle(inVolume mountPoint: String) throws -> URL {
        let volume = URL(fileURLWithPath: mountPoint, isDirectory: true)
        let direct = volume.appendingPathComponent("QDock.app")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: mountPoint)
        guard let appName = entries.first(where: { $0.hasSuffix(".app") }) else {
            throw AppUpdateError.appBundleNotFoundInDMG
        }
        return volume.appendingPathComponent(appName)
    }

    // MARK: - Copy into place

    /// Where the update should land: wherever the running bundle lives, or
    /// /Applications when running outside a bundle (e.g. `swift run`).
    static func defaultInstallDirectory() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    private func copyApp(from appSource: URL, intoDirectory directory: URL) async throws -> URL {
        do {
            return try await copyAppOnce(from: appSource, intoDirectory: directory)
        } catch {
            // Mirror the CLI installer: retry in ~/Applications when the
            // primary location is not writable.
            let fallback = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
            guard directory.path == "/Applications", isPermissionError(error) else { throw error }
            return try await copyAppOnce(from: appSource, intoDirectory: fallback)
        }
    }

    private func copyAppOnce(from appSource: URL, intoDirectory directory: URL) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let target = directory.appendingPathComponent(appSource.lastPathComponent)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        _ = try await runCommand("/usr/bin/ditto", arguments: [appSource.path, target.path])
        return target
    }

    private func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError].contains(nsError.code) {
            return true
        }
        return (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(EACCES)
    }

    // MARK: - Process helper

    private func runCommand(_ executablePath: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        process.standardOutput = stdout
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

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        guard status == 0 else {
            let command = (executablePath as NSString).lastPathComponent
            throw AppUpdateError.commandFailed(command: command, status: status)
        }
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}

private extension SHA256 {
    static func digest(_ digest: SHA256Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct GitHubReleaseResponse: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String
    }

    let tagName: String
    let htmlUrl: String
    let assets: [Asset]?
}
