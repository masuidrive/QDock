import Foundation

/// Runs short-lived helper subprocesses with a hard timeout.
///
/// Reads stdout on a background queue BEFORE waiting for exit so a full pipe
/// buffer can never deadlock the child, and terminates the child when it
/// exceeds the deadline so callers are always bounded (a hung login shell or
/// locked keychain must never wedge a refresh cycle).
enum SubprocessRunner {
    struct RunResult {
        let status: Int32
        let stdout: Data
    }

    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> RunResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var outputData = Data()

        DispatchQueue.global(qos: .utility).async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            // The reader block reaps the child once it dies; SIGKILL is the
            // last resort for a child that ignores SIGTERM.
            if semaphore.wait(timeout: .now() + 1.0) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            return nil
        }

        return RunResult(status: process.terminationStatus, stdout: outputData)
    }

    /// Convenience for `which`-style lookups: returns trimmed stdout on exit 0.
    static func runForString(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> String? {
        guard let result = run(executable: executable, arguments: arguments, timeout: timeout),
              result.status == 0,
              let string = String(data: result.stdout, encoding: .utf8) else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
