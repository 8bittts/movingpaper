import SwiftUI

@main
struct MovingPaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu bar app — no main window scene needed.
        // Keep a minimal scene so the dockless app can still use the SwiftUI app lifecycle.
        Settings {
            EmptyView()
        }
        .commands {
            // Lifecycle-only Settings scene. Hide the system Settings command
            // so Cmd-, and the app menu cannot open a blank window.
            CommandGroup(replacing: .appSettings) {}
        }
    }
}
