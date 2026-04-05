import AppKit
import Combine

/// Menu bar status item with wallpaper controls.
/// Provides file picker, pause/resume, and current state display.
@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let wallpaperManager: WallpaperManager
    private var cancellables = Set<AnyCancellable>()

    init(wallpaperManager: WallpaperManager) {
        self.wallpaperManager = wallpaperManager

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "photo.on.rectangle.angled",
                accessibilityDescription: "MovingPaper"
            )
        }
        self.statusItem = item

        rebuildMenu()

        // Rebuild menu when state changes
        wallpaperManager.$currentFileURL
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)

        wallpaperManager.$isPaused
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Current file display
        if let name = wallpaperManager.currentFileName {
            let fileItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            fileItem.isEnabled = false
            menu.addItem(fileItem)
            menu.addItem(.separator())

            // Pause / Resume
            let pauseTitle = wallpaperManager.isPaused ? "Resume" : "Pause"
            let pauseKey = wallpaperManager.isPaused ? "r" : "p"
            let pauseItem = NSMenuItem(
                title: pauseTitle,
                action: #selector(togglePause),
                keyEquivalent: pauseKey
            )
            pauseItem.target = self
            menu.addItem(pauseItem)

            // Clear wallpaper
            let clearItem = NSMenuItem(
                title: "Remove Wallpaper",
                action: #selector(clearWallpaper),
                keyEquivalent: ""
            )
            clearItem.target = self
            menu.addItem(clearItem)

            menu.addItem(.separator())
        }

        // Choose file
        let chooseItem = NSMenuItem(
            title: "Choose File...",
            action: #selector(chooseFile),
            keyEquivalent: "o"
        )
        chooseItem.target = self
        menu.addItem(chooseItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit MovingPaper",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func chooseFile() {
        wallpaperManager.selectFile()
    }

    @objc private func togglePause() {
        wallpaperManager.togglePause()
    }

    @objc private func clearWallpaper() {
        wallpaperManager.clearWallpaper()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
