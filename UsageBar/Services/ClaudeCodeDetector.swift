import Foundation

/// Multi-strategy detector for Claude Code installation
/// Tries several approaches in order of reliability
final class ClaudeCodeDetector {

    /// Detection result with details about what was found
    struct DetectionResult {
        let isDetected: Bool
        let strategy: Strategy
        let configDir: URL?
        let cliPath: String?
        let hasOAuthCredentials: Bool
        let hasApiKey: Bool
        let hasSessions: Bool
        let accountEmail: String?
        let message: String

        static var notFound: DetectionResult {
            DetectionResult(
                isDetected: false,
                strategy: .none,
                configDir: nil,
                cliPath: nil,
                hasOAuthCredentials: false,
                hasApiKey: false,
                hasSessions: false,
                accountEmail: nil,
                message: "Claude Code not detected"
            )
        }
    }

    enum Strategy: String, CaseIterable {
        case defaultPath      // ~/.claude exists
        case envVariable      // CLAUDE_CONFIG_DIR is set
        case customPath       // User-specified path
        case cliBinary        // `claude` binary found in PATH
        case keychainOnly     // Only Keychain credentials found (no local files)
        case none
    }

    /// The resolved config directory
    private(set) var resolvedConfigDir: URL?

    /// User-specified custom path (from settings)
    var customConfigPath: String? {
        didSet {
            UserDefaults.standard.set(customConfigPath, forKey: "claudeCodeCustomPath")
        }
    }

    init() {
        customConfigPath = UserDefaults.standard.string(forKey: "claudeCodeCustomPath")
    }

    // MARK: - Main Detection

    /// Run all detection strategies and return the best result
    func detect() -> DetectionResult {
        // Strategy 1: Custom path (highest priority — user explicitly set it)
        if let custom = customConfigPath, !custom.isEmpty {
            let result = checkPath(URL(fileURLWithPath: expandTilde(custom)), strategy: .customPath)
            if result.isDetected {
                resolvedConfigDir = result.configDir
                return result
            }
        }

        // Strategy 2: CLAUDE_CONFIG_DIR environment variable
        if let envDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            let result = checkPath(URL(fileURLWithPath: envDir), strategy: .envVariable)
            if result.isDetected {
                resolvedConfigDir = result.configDir
                return result
            }
        }

        // Strategy 3: Default path ~/.claude
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let defaultResult = checkPath(defaultPath, strategy: .defaultPath)
        if defaultResult.isDetected {
            resolvedConfigDir = defaultResult.configDir
            return defaultResult
        }

        // Strategy 4: Check CLI binary existence
        let cliResult = checkCLI()
        if cliResult.isDetected {
            resolvedConfigDir = cliResult.configDir
            return cliResult
        }

        // Strategy 5: Keychain-only (credentials exist but no local files)
        let keychainResult = checkKeychainOnly()
        if keychainResult.isDetected {
            return keychainResult
        }

        return .notFound
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

        // Check global config for account info
        let globalConfig = readGlobalConfig()
        let email = globalConfig?.oauthAccount?.emailAddress

        // Check credentials
        let hasOAuth = ClaudeKeychainReader.hasCredentials
        let hasApiKey = checkForApiKeyEnv()

        let detected = hasSessions || hasSettings || hasOAuth
        let message = buildMessage(
            strategy: strategy,
            path: url.path,
            hasSessions: hasSessions,
            hasOAuth: hasOAuth,
            hasApiKey: hasApiKey,
            email: email
        )

        return DetectionResult(
            isDetected: detected,
            strategy: strategy,
            configDir: url,
            cliPath: findCLIPath(),
            hasOAuthCredentials: hasOAuth,
            hasApiKey: hasApiKey,
            hasSessions: hasSessions,
            accountEmail: email,
            message: message
        )
    }

    private func checkCLI() -> DetectionResult {
        guard let cliPath = findCLIPath() else {
            return .notFound
        }

        // CLI exists, try to infer config dir
        // Claude Code always uses ~/.claude unless CLAUDE_CONFIG_DIR is set
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")

        return DetectionResult(
            isDetected: true,
            strategy: .cliBinary,
            configDir: FileManager.default.fileExists(atPath: defaultPath.path) ? defaultPath : nil,
            cliPath: cliPath,
            hasOAuthCredentials: ClaudeKeychainReader.hasCredentials,
            hasApiKey: checkForApiKeyEnv(),
            hasSessions: false,
            accountEmail: nil,
            message: "Claude Code CLI found at \(cliPath), but no session data yet"
        )
    }

    private func checkKeychainOnly() -> DetectionResult {
        guard ClaudeKeychainReader.hasCredentials else {
            return .notFound
        }

        let email = readGlobalConfig()?.oauthAccount?.emailAddress

        return DetectionResult(
            isDetected: true,
            strategy: .keychainOnly,
            configDir: nil,
            cliPath: findCLIPath(),
            hasOAuthCredentials: true,
            hasApiKey: false,
            hasSessions: false,
            accountEmail: email,
            message: "OAuth credentials found in Keychain but no local data directory. You can use the Anthropic API fallback."
        )
    }

    // MARK: - Helpers

    private func findCLIPath() -> String? {
        // Check common locations
        let commonPaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/claude",
        ]

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try `which claude` as last resort
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
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

    private func checkForApiKeyEnv() -> Bool {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil
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
        hasOAuth: Bool,
        hasApiKey: Bool,
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
        case .cliBinary, .keychainOnly, .none:
            break
        }

        if let email = email {
            parts.append("Account: \(email)")
        }

        if hasOAuth {
            parts.append("OAuth: active")
        } else if hasApiKey {
            parts.append("API key: found")
        }

        if hasSessions {
            parts.append("Sessions: available")
        }

        return parts.joined(separator: " | ")
    }
}
