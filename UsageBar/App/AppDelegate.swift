import AppKit
import SwiftUI

/// AppDelegate managing the NSStatusItem and NSPopover for the menu bar app
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var appState: AppState!
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock
        NSApp.setActivationPolicy(.accessory)

        // Initialize state
        appState = AppState()

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "chart.bar.fill",
                accessibilityDescription: "UsageBar"
            )
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

        // Observe menu bar text changes
        Task { @MainActor in
            // Periodically update the menu bar text
            while true {
                updateMenuBarText()
                try? await Task.sleep(for: .seconds(30))
            }
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

    @MainActor private func updateMenuBarText() {
        if let text = appState.menuBarText {
            statusItem.button?.title = " \(text)"
        } else {
            statusItem.button?.title = ""
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        appState.refreshService.stopAutoRefresh()
    }
}

/// Root view inside the popover
struct PopoverContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if appState.selectedProvider != nil {
                ProviderDetailView(appState: appState)
            } else if appState.showingSettings {
                SettingsView(appState: appState)
            } else {
                DashboardView(appState: appState)
            }
        }
        .frame(width: 380, height: 520)
    }
}
