import Foundation

/// JSON-RPC client that communicates with `codex app-server` via stdio
final class CodexAppServer {

    private var requestId = 0
    private let maxBufferSize = 262_144
    private static let pathCacheLock = NSLock()
    private static var cachedCodexPath: String?
    private static var cachedCodexPathDate: Date?
    private static let codexPathCacheTTL: TimeInterval = 300

    /// Fetch rate limits from codex app-server
    /// Launches the process, performs JSON-RPC handshake, queries rate limits, then terminates
    func fetchRateLimits(apiKey: String? = nil) async throws -> RateLimitsResult {
        // Find codex binary
        guard let codexPath = findCodexBinary() else {
            throw ProviderError.notInstalled
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        // Set environment — ensure node is in PATH for NVM installations
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        if let apiKey, !apiKey.isEmpty {
            env["OPENAI_API_KEY"] = apiKey
        }
        // Add the codex binary's directory to PATH so node can be found
        let codexDir = (codexPath as NSString).deletingLastPathComponent
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(codexDir):\(existingPath)"
        } else {
            env["PATH"] = codexDir
        }
        process.environment = env

        try process.run()

        defer {
            if process.isRunning {
                process.terminate()
            }
            // Reap off-thread so a terminated child never lingers as a zombie.
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
            }
        }

        // Step 1: Send initialize handshake (Codex app-server expects NDJSON JSON-RPC)
        let initializeId = try sendRequest(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "QDock",
                    "version": "1.0.0"
                ],
                "capabilities": NSNull()
            ],
            to: stdinPipe
        )

        // Read initialize response and surface protocol errors early.
        let initializeResponse = try await readResponse(for: initializeId, from: stdoutPipe, timeout: 10)
        if let error = initializeResponse.error {
            throw ProviderError.apiError(error.message ?? "initialize failed (code: \(error.code ?? -1))")
        }

        // Step 2: Send rate limits query
        let rateLimitRequestId = try sendRequest(
            method: "account/rateLimits/read",
            params: nil,
            to: stdinPipe
        )

        // Read rate limits response
        let response = try await readResponse(for: rateLimitRequestId, from: stdoutPipe, timeout: 10)

        // Terminate process
        process.terminate()

        guard let rateLimits = response.result?.resolvedRateLimits else {
            if let error = response.error {
                throw ProviderError.apiError(error.message ?? "Unknown JSON-RPC error (code: \(error.code ?? -1))")
            }
            throw ProviderError.parseError("No rate limits in response")
        }

        return rateLimits
    }

    // MARK: - Helpers

    private func nextId() -> Int {
        requestId += 1
        return requestId
    }

    @discardableResult
    private func sendRequest(method: String, params: [String: Any]?, to pipe: Pipe) throws -> Int {
        let id = nextId()
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method
        ]
        if let params {
            payload["params"] = params
        }

        // Current Codex app-server transport uses newline-delimited JSON-RPC.
        let requestData = try JSONSerialization.data(withJSONObject: payload, options: [])
        var lineData = requestData
        lineData.append(0x0A) // "\n"
        // write(contentsOf:) throws on a dead peer; the legacy write(_:) raises
        // an ObjC exception that would crash the app if codex dies mid-handshake.
        try pipe.fileHandleForWriting.write(contentsOf: lineData)
        return id
    }

    /// Bridges the pipe's event-driven reads into a continuation that is
    /// guaranteed to resume exactly once: on a matching response, EOF,
    /// deadline, or task cancellation. The old polling loop blocked forever
    /// in `availableData` when a live app-server sent nothing, which wedged
    /// the whole refresh pipeline and leaked the subprocess.
    private final class ResponseWaiter: @unchecked Sendable {
        private let lock = NSLock()
        private let handle: FileHandle
        private var continuation: CheckedContinuation<JsonRpcResponse, Error>?
        private var result: Result<JsonRpcResponse, Error>?
        var buffer = Data()

        init(handle: FileHandle) {
            self.handle = handle
        }

        var isFinished: Bool {
            lock.lock()
            defer { lock.unlock() }
            return result != nil
        }

        func install(_ continuation: CheckedContinuation<JsonRpcResponse, Error>) {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func finish(with result: Result<JsonRpcResponse, Error>) {
            lock.lock()
            guard self.result == nil else {
                lock.unlock()
                return
            }
            self.result = result
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()

            handle.readabilityHandler = nil
            continuation?.resume(with: result)
        }
    }

    private func readResponse(for requestId: Int, from pipe: Pipe, timeout: TimeInterval) async throws -> JsonRpcResponse {
        let handle = pipe.fileHandleForReading
        let maxBufferSize = self.maxBufferSize
        let waiter = ResponseWaiter(handle: handle)
        let decoder = JSONDecoder()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.install(continuation)

                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                    waiter.finish(with: .failure(ProviderError.apiError("Timeout waiting for codex app-server response")))
                }

                handle.readabilityHandler = { readHandle in
                    let chunk = readHandle.availableData
                    if chunk.isEmpty {
                        // EOF — process closed stdout or died.
                        waiter.finish(with: .failure(ProviderError.apiError("codex app-server closed connection")))
                        return
                    }

                    waiter.buffer.append(chunk)

                    // Parse newline-delimited JSON responses, ignoring notifications
                    while let newLineIndex = waiter.buffer.firstIndex(of: 0x0A) {
                        let lineData = Data(waiter.buffer[..<newLineIndex])
                        waiter.buffer.removeSubrange(waiter.buffer.startIndex...newLineIndex)

                        guard let line = String(data: lineData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                              !line.isEmpty,
                              let jsonData = line.data(using: .utf8) else { continue }

                        do {
                            let response = try decoder.decode(JsonRpcResponse.self, from: jsonData)
                            if response.id == requestId {
                                waiter.finish(with: .success(response))
                                return
                            }
                        } catch {
                            // If this payload is for our request id but malformed, fail fast.
                            if let decodedId = Self.extractResponseId(from: jsonData), decodedId == requestId {
                                waiter.finish(with: .failure(ProviderError.parseError("Failed to decode JSON-RPC response: \(error.localizedDescription)")))
                                return
                            }
                        }
                    }

                    if waiter.buffer.count > maxBufferSize {
                        waiter.finish(with: .failure(ProviderError.parseError("Response too large")))
                    }
                }

                // Close the race where finish() ran before the handler was set
                // (early cancellation/timeout): clearing is idempotent.
                if waiter.isFinished {
                    handle.readabilityHandler = nil
                }
            }
        } onCancel: {
            waiter.finish(with: .failure(CancellationError()))
        }
    }

    private static func extractResponseId(from data: Data) -> Int? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let id = jsonObject["id"] as? Int {
            return id
        }
        if let idString = jsonObject["id"] as? String {
            return Int(idString)
        }
        return nil
    }

    /// Public accessor for checking if codex binary exists
    func findCodexBinaryPublic() -> String? {
        findCodexBinary()
    }

    /// Find the codex binary in common locations
    private func findCodexBinary() -> String? {
        if let cached = cachedCodexBinaryIfFresh() {
            return cached
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var commonPaths = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/bin/codex",
            "\(home)/.local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.cargo/bin/codex",
        ]

        // Add NVM paths — scan all installed node versions
        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            for version in versions {
                commonPaths.append("\(nvmDir)/\(version)/bin/codex")
            }
        }

        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                cacheCodexBinary(path)
                return path
            }
        }

        // Try `which codex` via login shell to pick up user PATH (bounded:
        // a hung login shell must never wedge a refresh cycle).
        if let path = SubprocessRunner.runForString(
            executable: "/bin/zsh",
            arguments: ["-l", "-c", "which codex"],
            timeout: 5.0
        ), FileManager.default.isExecutableFile(atPath: path) {
            cacheCodexBinary(path)
            return path
        }

        return nil
    }

    private func cachedCodexBinaryIfFresh() -> String? {
        Self.pathCacheLock.lock()
        defer { Self.pathCacheLock.unlock() }

        guard let cachedPath = Self.cachedCodexPath,
              let cachedDate = Self.cachedCodexPathDate,
              Date().timeIntervalSince(cachedDate) < Self.codexPathCacheTTL,
              FileManager.default.isExecutableFile(atPath: cachedPath) else {
            return nil
        }

        return cachedPath
    }

    private func cacheCodexBinary(_ path: String) {
        Self.pathCacheLock.lock()
        Self.cachedCodexPath = path
        Self.cachedCodexPathDate = Date()
        Self.pathCacheLock.unlock()
    }
}
