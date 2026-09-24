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
    private var menuBarIconCache: [MenuBarImageKey: NSImage] = [:]
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
        popover.appearance = appState.appearanceMode.nsAppearance

        let contentView = PopoverContentView(appState: appState)
        let hostingController = NSHostingController(rootView: contentView)
        // Let the popover hug the dashboard's natural height instead of a fixed 520.
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController

        appState.onAppearanceModeChanged = { [weak self] mode in
            Task { @MainActor in
                guard let self else { return }
                self.popover.appearance = mode.nsAppearance
                self.tintPopoverChrome()
            }
        }

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

        // Set up update notifications. UNUserNotificationCenter raises
        // NSInternalInconsistencyException without a real app bundle, so
        // skip when running as a bare binary (swift run / .build/debug).
        if NotificationCapability.isAvailable {
            appState.setupUpdateNotifications()
            UNUserNotificationCenter.current().delegate = self
        }

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

    @MainActor
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            tintPopoverChrome()

            // Refresh on open only when data is older than the user's
            // chosen interval (e.g. after machine sleep)
            AppLog.refresh.info("popover opened")
            Task {
                await appState.refreshIfStale()
            }
        }
    }

    /// Paints the popover frame (including the anchor arrow) in the same
    /// color as the dashboard panel, so the popover reads as one flat
    /// surface instead of system material behind the view. In Glass mode
    /// the tint is cleared so the native material (Liquid Glass on
    /// macOS 26+) shows through.
    @MainActor
    private func tintPopoverChrome() {
        guard let frameView = popover.contentViewController?.view.window?.contentView?.superview else {
            return
        }
        frameView.wantsLayer = true

        if appState.appearanceMode.isGlass {
            frameView.layer?.backgroundColor = nil
            return
        }

        let appearance = popover.appearance ?? NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let panel = isDark
            ? NSColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1)   // #141414
            : NSColor.white
        frameView.layer?.backgroundColor = panel.cgColor
    }

    @MainActor
    private func applyMenuBarPresentation(_ presentation: MenuBarPresentation) {
        guard let button = statusItem.button else { return }

        let image = cachedMenuBarImage(for: presentation)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.image = image
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""
        let usageSummary = presentation.usages
            .map { usage in
                let used = "\(usage.provider.displayName) \(usage.roundedPercent)% used"
                guard let elapsed = usage.roundedTimeProgressPercent else { return used }
                return "\(used), \(elapsed)% elapsed"
            }
            .joined(separator: ", ")
        let accessibilityLabel = usageSummary.isEmpty ? "QDock" : "QDock, \(usageSummary)"
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        statusItem.length = image.size.width + 4
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

    private struct MenuBarImageKey: Hashable {
        let claudePercent: Int?
        let claudeTimeProgress: Int?
        let codexPercent: Int?
        let codexTimeProgress: Int?
        let showsPercentText: Bool
    }

    private func cachedMenuBarImage(for presentation: MenuBarPresentation) -> NSImage {
        let key = MenuBarImageKey(
            claudePercent: presentation.usages.first { $0.provider == .claude }?.roundedPercent,
            claudeTimeProgress: presentation.usages
                .first { $0.provider == .claude }?.roundedTimeProgressPercent,
            codexPercent: presentation.usages.first { $0.provider == .codex }?.roundedPercent,
            codexTimeProgress: presentation.usages
                .first { $0.provider == .codex }?.roundedTimeProgressPercent,
            showsPercentText: presentation.showsPercentText
        )
        if let cached = menuBarIconCache[key] {
            return cached
        }

        let image = createMenuBarImage(key: key)
        menuBarIconCache[key] = image
        return image
    }

    private func createMenuBarImage(key: MenuBarImageKey) -> NSImage {
        let iconSize: CGFloat = 18
        let gap: CGFloat = 3
        let usages: [(provider: MenuBarProvider, percent: Int, timeProgress: Int?)] = [
            key.claudePercent.map { (.claude, $0, key.claudeTimeProgress) },
            key.codexPercent.map { (.codex, $0, key.codexTimeProgress) },
        ].compactMap { $0 }

        let textFont = NSFont.monospacedDigitSystemFont(
            ofSize: usages.count > 1 ? 8 : 11,
            weight: .medium
        )
        let textWidth = usages.map { usage in
            let text = "\(usage.percent)%" as NSString
            return ceil(text.size(withAttributes: [.font: textFont]).width)
        }.max() ?? 0
        let showsText = key.showsPercentText && !usages.isEmpty
        let imageWidth = iconSize + (showsText ? gap + textWidth : 0)

        let image = NSImage(size: NSSize(width: imageWidth, height: iconSize), flipped: false) { _ in
            let center = NSPoint(x: iconSize / 2, y: iconSize / 2)

            if usages.count > 1 {
                Self.drawProgressRing(
                    center: center,
                    radius: 7,
                    lineWidth: 2,
                    percent: key.claudePercent,
                    timeProgressPercent: key.claudeTimeProgress,
                    color: ColorTheme.nsColor(for: .claude)
                )
                Self.drawProgressRing(
                    center: center,
                    radius: 4.75,
                    lineWidth: 2,
                    percent: key.codexPercent,
                    timeProgressPercent: key.codexTimeProgress,
                    color: ColorTheme.nsColor(for: .codex)
                )
            } else if let usage = usages.first {
                Self.drawProgressRing(
                    center: center,
                    radius: 7,
                    lineWidth: 2.5,
                    percent: usage.percent,
                    timeProgressPercent: usage.timeProgress,
                    color: ColorTheme.nsColor(for: usage.provider)
                )
            } else {
                Self.drawProgressRing(
                    center: center,
                    radius: 7,
                    lineWidth: 2.5,
                    percent: nil,
                    timeProgressPercent: nil,
                    color: .clear
                )
            }

            guard showsText else { return true }
            let textX = iconSize + gap
            if usages.count > 1 {
                Self.drawMenuBarText(
                    "\(key.claudePercent ?? 0)%",
                    provider: .claude,
                    font: textFont,
                    x: textX,
                    y: 9
                )
                Self.drawMenuBarText(
                    "\(key.codexPercent ?? 0)%",
                    provider: .codex,
                    font: textFont,
                    x: textX,
                    y: 0
                )
            } else if let usage = usages.first {
                Self.drawMenuBarText(
                    "\(usage.percent)%",
                    provider: usage.provider,
                    font: textFont,
                    x: textX,
                    y: 2.5
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawProgressRing(
        center: NSPoint,
        radius: CGFloat,
        lineWidth: CGFloat,
        percent: Int?,
        timeProgressPercent: Int?,
        color: NSColor
    ) {
        let track = NSBezierPath(ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        track.lineWidth = lineWidth
        NSColor.systemGray.withAlphaComponent(0.3).setStroke()
        track.stroke()

        if let percent, percent > 0 {
            let progress = NSBezierPath()
            progress.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - (360 * CGFloat(min(percent, 100)) / 100),
                clockwise: true
            )
            progress.lineWidth = lineWidth
            progress.lineCapStyle = .round
            color.setStroke()
            progress.stroke()
        }

        guard let timeProgressPercent else { return }
        let elapsed = CGFloat(max(0, min(timeProgressPercent, 100))) / 100
        let angle = (90 - 360 * elapsed) * .pi / 180
        let markerCenter = NSPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
        let markerRadius = min(1.5, lineWidth * 0.7)
        let marker = NSBezierPath(ovalIn: NSRect(
            x: markerCenter.x - markerRadius,
            y: markerCenter.y - markerRadius,
            width: markerRadius * 2,
            height: markerRadius * 2
        ))
        ColorTheme.nsTimeProgressMarker.setFill()
        marker.fill()
    }

    private static func drawMenuBarText(
        _ text: String,
        provider: MenuBarProvider,
        font: NSFont,
        x: CGFloat,
        y: CGFloat
    ) {
        (text as NSString).draw(
            at: NSPoint(x: x, y: y),
            withAttributes: [
                .font: font,
                .foregroundColor: ColorTheme.nsColor(for: provider),
            ]
        )
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
        // appState is nil when a second instance terminates before finishing
        // launch (single-instance lock) — force-unwrapping here crashed.
        if let appState {
            appState.onMenuBarPresentationChanged = nil
            appState.providerManager.onStateChanged = nil
            appState.sessionWatcher.stopWatching()
            appState.refreshService.stopAutoRefresh()
        }
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
            if appState.showingSettings {
                SettingsView(appState: appState)
                    .frame(height: 520, alignment: .top)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                // The dashboard sizes to its content, like the site popover.
                DashboardView(appState: appState)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.showingSettings)
        .frame(width: 380, alignment: .top)
    }
}
