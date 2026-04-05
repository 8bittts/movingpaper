import SwiftUI

@main
struct MovingPaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu bar app — no main window scene needed.
        // Settings window available via Cmd+, or status bar menu.
        Settings {
            SettingsView()
        }
    }
}
