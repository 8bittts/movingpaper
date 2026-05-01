import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var wallpaperManager: WallpaperManager?
    private var updater: MovingPaperUpdater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIdentityDefaultsMigration.migrateIfNeeded()
        installApplicationIcon()

        // Menu bar only — no Dock icon, no Cmd+Tab entry
        AppPresentation.returnToAccessory()

        let manager = WallpaperManager()
        self.wallpaperManager = manager

        let sparkleUpdater = MovingPaperUpdater()
        self.updater = sparkleUpdater

        self.statusBar = StatusBarController(
            wallpaperManager: manager,
            updater: sparkleUpdater
        )

        sparkleUpdater.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperManager?.tearDown()
    }

    private func installApplicationIcon() {
        guard
            let iconURL = Bundle.module.url(
                forResource: "movingpaper-icon",
                withExtension: "png",
                subdirectory: "Resources"
            ),
            let icon = NSImage(contentsOf: iconURL)
        else {
            return
        }

        NSApp.applicationIconImage = icon
    }
}
