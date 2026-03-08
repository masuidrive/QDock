import AppKit
import Darwin
import SwiftUI
import UserNotifications

/// AppDelegate managing the NSStatusItem and NSPopover for the menu bar app
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var appState: AppState!
    private var eventMonitor: Any?
    private var screenParametersObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?
    private var menuBarIconCache: [Int: NSImage] = [:]
    private var singleInstanceLockFD: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)

        guard acquireSingleInstanceLock() else {
            NSApp.terminate(nil)
            return
        }

        // Initialize state
        appState = AppState()

        // Create status bar item with fixed length (updated dynamically)
        statusItem = NSStatusBar.system.statusItem(withLength: 18)

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.animates = true

        let contentView = PopoverContentView(appState: appState)
        popover.contentViewController = NSHostingController(rootView: contentView)

        appState.onMenuBarPresentationChanged = { [weak self] presentation in
            Task { @MainActor in
                self?.applyMenuBarPresentation(presentation)
            }
        }

        // Monitor for clicks outside to close popover
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }

        // Set up update notifications
        appState.setupUpdateNotifications()
        UNUserNotificationCenter.current().delegate = self

        // Initial data load
        Task {
            await appState.initialLoad()
        }
        applyMenuBarPresentation(appState.menuBarPresentation)
        installMenuBarRefreshObservers()

        // Re-apply once after the status item is fully attached to a screen.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyMenuBarPresentation(self.appState.menuBarPresentation)
            self.closeUnexpectedSettingsWindowIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            closeUnexpectedSettingsWindowIfNeeded()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()

            // Refresh data when popover opens
            Task {
                await appState.manualRefresh()
            }
        }
    }

    @MainActor
    private func applyMenuBarPresentation(_ presentation: MenuBarPresentation) {
        guard let button = statusItem.button else { return }

        let clampedPercent = max(0, min(100, presentation.roundedPercent))
        button.image = cachedProgressIcon(percent: clampedPercent)

        if let text = presentation.text, !text.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: ColorTheme.nsColorForUsage(presentation.percent),
            ]
            button.attributedTitle = NSAttributedString(string: " \(text)", attributes: attributes)

            let textWidth = ceil((text as NSString).size(withAttributes: attributes).width)
            // icon + gap + text + right breathing space
            statusItem.length = ceil(18 + 3 + textWidth + 6)
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            statusItem.length = 18
        }
        button.needsDisplay = true
    }

    // MARK: - Menu Bar Refresh

    private func installMenuBarRefreshObservers() {
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMenuBarForCurrentScreen()
            }
        }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMenuBarForCurrentScreen()
            }
        }
    }

    private func acquireSingleInstanceLock() -> Bool {
        let lockPath = "/tmp/com.qdock.instance.lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return true } // Fallback to not blocking launch if lock file cannot be created.

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }

        // Keep fd open for process lifetime.
        singleInstanceLockFD = fd
        return true
    }

    @MainActor
    private func refreshMenuBarForCurrentScreen() {
        menuBarIconCache.removeAll()
        applyMenuBarPresentation(appState.menuBarPresentation)
    }

    @MainActor
    private func closeUnexpectedSettingsWindowIfNeeded() {
        for window in NSApp.windows where window.title == "QDock Settings" {
            window.orderOut(nil)
            window.close()
        }
    }

    // MARK: - Progress Icon

    private func cachedProgressIcon(percent: Int) -> NSImage {
        if let cached = menuBarIconCache[percent] {
            return cached
        }
        let image = createProgressIcon(percent: Double(percent))
        menuBarIconCache[percent] = image
        return image
    }

    private func createProgressIcon(percent: Double) -> NSImage {
        let size: CGFloat = 18
        let lineWidth: CGFloat = 2.5
        let image = NSImage(size: NSSize(width: size, height: size))

        // Draw progress circle
        image.lockFocus()

        let iconRect = NSRect(x: lineWidth / 2, y: lineWidth / 2,
                              width: size - lineWidth, height: size - lineWidth)
        let center = NSPoint(x: size / 2, y: size / 2)
        let radius = (size - lineWidth) / 2

        let bgPath = NSBezierPath(ovalIn: iconRect)
        bgPath.lineWidth = lineWidth
        NSColor.systemGray.withAlphaComponent(0.3).setStroke()
        bgPath.stroke()

        if percent > 0 {
            let startAngle: CGFloat = 90
            let endAngle: CGFloat = 90 - (360 * min(percent, 100) / 100)

            let progressPath = NSBezierPath()
            progressPath.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: true
            )
            progressPath.lineWidth = lineWidth
            progressPath.lineCapStyle = .round
            ColorTheme.nsColorForUsage(percent).setStroke()
            progressPath.stroke()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        appState.onMenuBarPresentationChanged = nil
        appState.providerManager.onStateChanged = nil
        appState.sessionWatcher.stopWatching()
        appState.refreshService.stopAutoRefresh()
        if singleInstanceLockFD >= 0 {
            close(singleInstanceLockFD)
            singleInstanceLockFD = -1
        }
    }
}

// MARK: - Notification Actions

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == AppState.updateActionIdentifier {
            Task { @MainActor in
                await appState.installAvailableUpdate()
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Root view inside the popover with animated transitions
@MainActor
struct PopoverContentView: View {
    let appState: AppState

    var body: some View {
        Group {
            if appState.selectedProvider != nil {
                ProviderDetailView(appState: appState)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if appState.showingSettings {
                SettingsView(appState: appState)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                DashboardView(appState: appState)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.selectedProvider?.id)
        .animation(.easeInOut(duration: 0.25), value: appState.showingSettings)
        .frame(width: 380, height: 520, alignment: .top)
    }
}
