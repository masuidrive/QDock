import Foundation

/// Multi-strategy detector for Claude Code installation.
/// NEVER touches Keychain during detection — only uses file system checks.
/// Keychain is only accessed later by the provider when a token is actually needed.
final class ClaudeCodeDetector {
    private let lock = NSLock()
    private var cachedResult: DetectionResult?
    private var cacheDate: Date?
    private let cacheTTL: TimeInterval = 30

    /// Detection result with details about what was found
    struct DetectionResult {
        let isDetected: Bool
        let strategy: Strategy
        let configDir: URL?
        let cliPath: String?
        let hasCredentialsFile: Bool
        let hasSessions: Bool
        let accountEmail: String?
        let message: String

        static var notFound: DetectionResult {
            DetectionResult(
                isDetected: false,
                strategy: .none,
                configDir: nil,
                cliPath: nil,
                hasCredentialsFile: false,
                hasSessions: false,
                accountEmail: nil,
                message: "Claude not detected"
            )
        }
    }

    enum Strategy: String, CaseIterable {
        case defaultPath      // ~/.claude exists
        case envVariable      // CLAUDE_CONFIG_DIR is set
        case customPath       // User-specified path
        case cliBinary        // `claude` binary found in PATH
        case none
    }

    /// The resolved config directory
    private var resolvedConfigDirStorage: URL?
    var resolvedConfigDir: URL? {
        lock.lock()
        defer { lock.unlock() }
        return resolvedConfigDirStorage
    }

    /// User-specified custom path (from settings)
    var customConfigPath: String? {
        didSet {
            UserDefaults.standard.set(customConfigPath, forKey: "claudeCodeCustomPath")
            invalidateCache()
        }
    }

    init() {
        customConfigPath = UserDefaults.standard.string(forKey: "claudeCodeCustomPath")
    }

    // MARK: - Main Detection

    /// Run all detection strategies and return the best result.
    /// NEVER touches Keychain — only checks file system and CLI binary.
    func detect(forceRefresh: Bool = false) -> DetectionResult {
        if !forceRefresh, let cached = cachedResultIfFresh() {
            setResolvedConfigDir(cached.configDir)
            return cached
        }

        let result = detectUncached()
        setCachedResult(result)
        setResolvedConfigDir(result.configDir)
        return result
    }

    func invalidateCache() {
        lock.lock()
        cachedResult = nil
        cacheDate = nil
        lock.unlock()
    }

    private func detectUncached() -> DetectionResult {
        // Strategy 1: Custom path (highest priority — user explicitly set it)
        if let custom = customConfigPath, !custom.isEmpty {
            let result = checkPath(URL(fileURLWithPath: expandTilde(custom)), strategy: .customPath)
            if result.isDetected {
                return result
            }
        }

        // Strategy 2: CLAUDE_CONFIG_DIR environment variable
        if let envDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            let result = checkPath(URL(fileURLWithPath: envDir), strategy: .envVariable)
            if result.isDetected {
                return result
            }
        }

        // Strategy 3: Default path ~/.claude
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let defaultResult = checkPath(defaultPath, strategy: .defaultPath)
        if defaultResult.isDetected {
            return defaultResult
        }

        // Strategy 4: Check CLI binary existence
        let cliResult = checkCLI()
        if cliResult.isDetected {
            return cliResult
        }

        // NO Keychain-only strategy — we never touch Keychain during detection
        return .notFound
    }

    private func cachedResultIfFresh() -> DetectionResult? {
        lock.lock()
        defer { lock.unlock() }

        guard let cachedResult,
              let cacheDate,
              Date().timeIntervalSince(cacheDate) < cacheTTL else {
            return nil
        }
        return cachedResult
    }

    private func setCachedResult(_ result: DetectionResult) {
        lock.lock()
        cachedResult = result
        cacheDate = Date()
        lock.unlock()
    }

    private func setResolvedConfigDir(_ url: URL?) {
        lock.lock()
        resolvedConfigDirStorage = url
        lock.unlock()
    }

    // MARK: - Individual Strategies

    private func checkPath(_ url: URL, strategy: Strategy) -> DetectionResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return .notFound
        }

        // Check for projects directory
        let projectsDir = url.appendingPathComponent("projects")
        let hasSessions = fm.fileExists(atPath: projectsDir.path)

        // Check for settings
        let settingsFile = url.appendingPathComponent("settings.json")
        let hasSettings = fm.fileExists(atPath: settingsFile.path)

        // Check for credentials FILE (not Keychain!)
        let credFile = url.appendingPathComponent(".credentials.json")
        let hasCredFile = fm.fileExists(atPath: credFile.path)

        // Check global config for account info
        let globalConfig = readGlobalConfig()
        let email = globalConfig?.oauthAccount?.emailAddress

        // Detected if directory has anything meaningful
        let detected = hasSessions || hasSettings || hasCredFile
            || fm.fileExists(atPath: url.appendingPathComponent("statsig").path)
        let message = buildMessage(
            strategy: strategy,
            path: url.path,
            hasSessions: hasSessions,
            hasCredFile: hasCredFile,
            email: email
        )

        return DetectionResult(
            isDetected: detected,
            strategy: strategy,
            configDir: url,
            cliPath: findCLIPath(),
            hasCredentialsFile: hasCredFile,
            hasSessions: hasSessions,
            accountEmail: email,
            message: message
        )
    }

    private func checkCLI() -> DetectionResult {
        guard let cliPath = findCLIPath() else {
            return .notFound
        }

        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")

        return DetectionResult(
            isDetected: true,
            strategy: .cliBinary,
            configDir: FileManager.default.fileExists(atPath: defaultPath.path) ? defaultPath : nil,
            cliPath: cliPath,
            hasCredentialsFile: false,
            hasSessions: false,
            accountEmail: nil,
            message: "Claude CLI found at \(cliPath)"
        )
    }

    // MARK: - Helpers

    private func findCLIPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.cargo/bin/claude",
        ]

        var candidatePaths = commonPaths

        // Include NVM-managed Node bins for globally installed npm CLIs.
        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            for version in versions {
                candidatePaths.append("\(nvmDir)/\(version)/bin/claude")
            }
        }

        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try login shell PATH as last resort.
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = path, !path.isEmpty {
                    return path
                }
            }
        } catch {}

        return nil
    }

    private func readGlobalConfig() -> ClaudeGlobalConfig? {
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? JSONDecoder().decode(ClaudeGlobalConfig.self, from: data)
    }

    private func expandTilde(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.path
                + String(path.dropFirst(1))
        }
        return path
    }

    private func buildMessage(
        strategy: Strategy,
        path: String,
        hasSessions: Bool,
        hasCredFile: Bool,
        email: String?
    ) -> String {
        var parts: [String] = []

        switch strategy {
        case .defaultPath:
            parts.append("Found at \(path)")
        case .envVariable:
            parts.append("Found via CLAUDE_CONFIG_DIR at \(path)")
        case .customPath:
            parts.append("Using custom path: \(path)")
        case .cliBinary, .none:
            break
        }

        if let email = email {
            parts.append("Account: \(email)")
        }

        if hasCredFile {
            parts.append("Credentials: file")
        }

        if hasSessions {
            parts.append("Sessions: available")
        }

        return parts.joined(separator: " | ")
    }
}
