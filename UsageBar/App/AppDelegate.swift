import AppKit
import SwiftUI

/// AppDelegate managing the NSStatusItem and NSPopover for the menu bar app
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var appState: AppState!
    private var eventMonitor: Any?
    private var menuBarImageCache: [String: NSImage] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)

        // Initialize state
        appState = AppState()

        // Create status bar item with fixed length (updated dynamically)
        statusItem = NSStatusBar.system.statusItem(withLength: 18)

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
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

        // Initial data load
        Task {
            await appState.initialLoad()
        }
        applyMenuBarPresentation(appState.menuBarPresentation)
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

        let cacheKey = "\(clampedPercent)_\(presentation.text ?? "")"
        let image: NSImage
        if let cached = menuBarImageCache[cacheKey] {
            image = cached
        } else {
            image = createMenuBarImage(
                percent: Double(clampedPercent),
                displayPercent: presentation.percent,
                text: presentation.text
            )
            menuBarImageCache[cacheKey] = image
        }
        button.image = image
        button.title = ""
        statusItem.length = image.size.width
    }

    // MARK: - Composite Menu Bar Image

    private func createMenuBarImage(percent: Double, displayPercent: Double, text: String?) -> NSImage {
        let iconSize: CGFloat = 18
        let lineWidth: CGFloat = 2.5
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let gap: CGFloat = 3

        var totalWidth = iconSize
        var textAttrs: [NSAttributedString.Key: Any]?
        var textSize: CGSize = .zero

        if let text = text {
            let color = ColorTheme.nsColorForUsage(displayPercent)
            textAttrs = [
                .font: font,
                .foregroundColor: color,
            ]
            textSize = (text as NSString).size(withAttributes: textAttrs)
            totalWidth += gap + ceil(textSize.width)
        }

        let width = ceil(totalWidth)
        let height = iconSize
        let scale: CGFloat = 2 // Always @2x for crisp rendering on all displays

        // Create bitmap at fixed @2x resolution for consistent sizing across displays
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale),
            pixelsHigh: Int(height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: NSSize(width: width, height: height))
        }
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return NSImage(size: NSSize(width: width, height: height))
        }
        NSGraphicsContext.current = ctx
        ctx.cgContext.scaleBy(x: scale, y: scale)

        // Draw progress circle
        let iconRect = NSRect(x: lineWidth / 2, y: lineWidth / 2,
                              width: iconSize - lineWidth, height: iconSize - lineWidth)
        let center = NSPoint(x: iconSize / 2, y: iconSize / 2)
        let radius = (iconSize - lineWidth) / 2

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

        // Draw text next to icon
        if let text = text, let attrs = textAttrs {
            let textY = (height - textSize.height) / 2
            (text as NSString).draw(at: NSPoint(x: iconSize + gap, y: textY), withAttributes: attrs)
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        appState.onMenuBarPresentationChanged = nil
        appState.providerManager.onStateChanged = nil
        appState.sessionWatcher.stopWatching()
        appState.refreshService.stopAutoRefresh()
    }
}

/// Root view inside the popover with animated transitions
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
