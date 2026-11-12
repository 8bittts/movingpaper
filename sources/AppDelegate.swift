import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var wallpaperManager: WallpaperManager?
    private var updater: MovingPaperUpdater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIdentityDefaultsMigration.migrateIfNeeded()

        let manager = WallpaperManager()
        self.wallpaperManager = manager

        // Evict stale cache entries off the main path; safe to drop if canceled.
        // Protect files the restored wallpapers still reference so an eviction
        // can't blank a live desktop.
        let protectedPaths = manager.referencedLocalPaths
        Task.detached(priority: .utility) {
            CacheJanitor.enforceDefaultPolicies(protecting: protectedPaths)
            CacheJanitor.pruneUnreferencedPhotosCaches(referencedPaths: protectedPaths)
        }

        let sparkleUpdater = MovingPaperUpdater()
        self.updater = sparkleUpdater

        self.statusBar = StatusBarController(
            wallpaperManager: manager,
            updater: sparkleUpdater
        )

        sparkleUpdater.start()
    }

    /// Opening the app while it runs must do something visible; returning false
    /// tells AppKit the app handled the reopen itself.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBar?.handleReopen()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        statusBar?.makeDockMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperManager?.tearDown()
    }
}
