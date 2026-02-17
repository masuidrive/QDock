import SwiftUI

@main
struct QDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar-only app — no main window
        Settings {
            EmptyView()
        }
    }
}
