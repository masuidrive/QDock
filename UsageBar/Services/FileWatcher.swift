import Foundation

/// Watches for file system changes to detect late Claude Code installation
/// or new session files being created
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let path: String
    private let onChange: () -> Void

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Start watching for changes
    func start() {
        // If the directory doesn't exist yet, watch the parent
        let watchPath: String
        let fm = FileManager.default

        if fm.fileExists(atPath: path) {
            watchPath = path
        } else {
            // Watch home directory for .claude creation
            watchPath = fm.homeDirectoryForCurrentUser.path
        }

        fileDescriptor = open(watchPath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .global(qos: .utility)
        )

        source?.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.onChange()
            }
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }

        source?.resume()
    }

    /// Stop watching
    func stop() {
        source?.cancel()
        source = nil
    }
}

/// Watches the ~/.claude/projects/ directory for new session files
/// and triggers a refresh when new data is available
@MainActor
final class SessionFileWatcher: ObservableObject {
    @Published var lastChangeDetected: Date?

    private var projectsWatcher: FileWatcher?
    private var claudeDirWatcher: FileWatcher?
    private var onSessionUpdate: (() async -> Void)?
    private var debounceTask: Task<Void, Never>?

    func configure(onSessionUpdate: @escaping () async -> Void) {
        self.onSessionUpdate = onSessionUpdate
    }

    func startWatching() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude")
        let projectsDir = claudeDir.appendingPathComponent("projects")

        // Watch projects directory for new/modified session files
        if FileManager.default.fileExists(atPath: projectsDir.path) {
            projectsWatcher = FileWatcher(path: projectsDir.path) { [weak self] in
                Task { @MainActor in
                    self?.handleChange()
                }
            }
            projectsWatcher?.start()
        }

        // Also watch .claude dir in case projects/ doesn't exist yet
        claudeDirWatcher = FileWatcher(path: claudeDir.path) { [weak self] in
            Task { @MainActor in
                // Check if projects dir appeared
                if FileManager.default.fileExists(atPath: projectsDir.path),
                   self?.projectsWatcher == nil {
                    self?.projectsWatcher = FileWatcher(path: projectsDir.path) { [weak self] in
                        Task { @MainActor in
                            self?.handleChange()
                        }
                    }
                    self?.projectsWatcher?.start()
                }
                self?.handleChange()
            }
        }
        claudeDirWatcher?.start()
    }

    func stopWatching() {
        projectsWatcher?.stop()
        projectsWatcher = nil
        claudeDirWatcher?.stop()
        claudeDirWatcher = nil
        debounceTask?.cancel()
    }

    /// Debounced handler — waits 2 seconds after last change before triggering refresh
    private func handleChange() {
        lastChangeDetected = Date()

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.onSessionUpdate?()
        }
    }
}
