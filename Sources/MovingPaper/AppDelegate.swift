import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var wallpaperManager: WallpaperManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — no Dock icon, no Cmd+Tab entry
        NSApp.setActivationPolicy(.accessory)

        let manager = WallpaperManager()
        self.wallpaperManager = manager

        self.statusBar = StatusBarController(wallpaperManager: manager)
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperManager?.tearDown()
    }
}
