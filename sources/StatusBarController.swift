import AppKit

/// Menu bar status item with wallpaper controls. Rebuilds its menu on demand
/// (via NSMenuDelegate.menuNeedsUpdate) so per-state-change Combine pipelines
/// don't throw NSMenuItems away dozens of times per second during typing or
/// download-progress updates.
@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let wallpaperManager: WallpaperManager
    private let updater: MovingPaperUpdater

    init(wallpaperManager: WallpaperManager, updater: MovingPaperUpdater) {
        self.wallpaperManager = wallpaperManager
        self.updater = updater
        super.init()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let icon = MenuBarIcon.brandIcon()
            icon.accessibilityDescription = "MovingPaper"
            button.image = icon
            button.toolTip = "MovingPaper"
        }
        let menu = NSMenu()
        // Manage enabled state ourselves; otherwise AppKit auto-enables any item
        // with a valid target/action, overriding e.g. the Check-for-Updates gate.
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
    }

    private func rebuildMenu(into menu: NSMenu) {
        menu.removeAllItems()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let rows = MenuSnapshot.rows(
            from: wallpaperManager.menuInput(
                appVersion: version,
                canCheckForUpdates: updater.canCheckForUpdates
            )
        )
        append(rows, to: menu)
    }

    private func append(_ rows: [MenuRow], to menu: NSMenu) {
        for row in rows {
            menu.addItem(makeItem(row))
        }
    }

    private func makeItem(_ row: MenuRow) -> NSMenuItem {
        switch row {
        case .disabled(let title):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case .separator:
            return .separator()
        case .sectionHeader(let title):
            return NSMenuItem.sectionHeader(title: title)
        case .command(let command):
            return makeCommandItem(command)
        case .submenu(let title, let rows):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = makeSubmenu(rows)
            return item
        case .item(let title, let checked, let children):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.state = checked ? .on : .off
            item.submenu = makeSubmenu(children)
            return item
        }
    }

    private func makeSubmenu(_ rows: [MenuRow]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        append(rows, to: menu)
        return menu
    }

    private func makeCommandItem(_ command: MenuCommand) -> NSMenuItem {
        let item = NSMenuItem(
            title: command.title,
            action: selector(for: command.id),
            keyEquivalent: command.keyEquivalent
        )
        item.target = self
        item.isEnabled = command.enabled
        item.state = command.checked ? .on : .off
        if let displayID = command.displayID {
            item.tag = Int(displayID)
        }
        return item
    }

    private func selector(for id: MenuCommandID) -> Selector {
        switch id {
        case .cancelDownload: #selector(cancelDownload)
        case .chooseFile: #selector(chooseFile(_:))
        case .pasteYouTube: #selector(pasteYouTube(_:))
        case .choosePhotos: #selector(choosePhotos(_:))
        case .shufflePhotos: #selector(shufflePhotos(_:))
        case .clearAll: #selector(clearAllWallpapers)
        case .clearDisplay: #selector(clearDisplayWallpaper(_:))
        case .toggleMute: #selector(toggleMute)
        case .togglePause: #selector(togglePause)
        case .setModeAllDesktops: #selector(setModeAllDesktops)
        case .setModePerDesktop: #selector(setModePerDesktop)
        case .checkForUpdates: #selector(checkForUpdates)
        case .openYEN: #selector(openYEN)
        case .quit: #selector(quit)
        }
    }

    private func optionalDisplayID(_ sender: NSMenuItem) -> CGDirectDisplayID? {
        sender.tag == 0 ? nil : CGDirectDisplayID(sender.tag)
    }

    // MARK: - Actions

    @objc private func chooseFile(_ sender: NSMenuItem) {
        wallpaperManager.selectFile(for: optionalDisplayID(sender))
    }

    @objc private func clearDisplayWallpaper(_ sender: NSMenuItem) {
        guard let displayID = optionalDisplayID(sender) else { return }
        wallpaperManager.clearWallpaper(for: displayID)
    }

    @objc private func clearAllWallpapers() {
        wallpaperManager.clearAllWallpapers()
    }

    @objc private func togglePause() {
        wallpaperManager.togglePause()
    }

    @objc private func toggleMute() {
        wallpaperManager.toggleMute()
    }

    @objc private func setModeAllDesktops() {
        wallpaperManager.setMode(.allDesktops)
    }

    @objc private func setModePerDesktop() {
        wallpaperManager.setMode(.perDesktop)
    }

    @objc private func pasteYouTube(_ sender: NSMenuItem) {
        let urlString = promptForYouTubeURL()
        guard let urlString else { return }
        wallpaperManager.setYouTubeWallpaper(urlString: urlString, for: optionalDisplayID(sender))
    }

    @objc private func cancelDownload() {
        wallpaperManager.cancelDownload()
    }

    private func promptForYouTubeURL() -> String? {
        AppPresentation.withForegroundActivation {
            let alert = NSAlert()
            alert.messageText = "Paste YouTube URL"
            alert.informativeText = "Enter a YouTube video URL to use as your wallpaper."
            alert.addButton(withTitle: "Start")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
            input.placeholderString = "https://youtube.com/watch?v=..."
            input.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            input.lineBreakMode = .byTruncatingMiddle
            input.usesSingleLineMode = true
            if let clip = NSPasteboard.general.string(forType: .string) {
                input.stringValue = clip
            }
            alert.accessoryView = input
            alert.window.initialFirstResponder = input

            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    @objc private func choosePhotos(_ sender: NSMenuItem) {
        presentPhotosPicker(for: optionalDisplayID(sender))
    }

    /// Foreground the app, run the Photos picker, and assign the pick (nil display = all).
    private func presentPhotosPicker(for displayID: CGDirectDisplayID?) {
        AppPresentation.promoteToForeground()
        Task {
            defer { AppPresentation.returnToAccessory() }
            let picker = PhotosPickerController()
            let url = await picker.run()
            guard let url else { return }
            wallpaperManager.setWallpaper(url: url, for: displayID)
        }
    }

    @objc private func shufflePhotos(_ sender: NSMenuItem) {
        wallpaperManager.shuffleFromPhotos(for: optionalDisplayID(sender))
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func openYEN() {
        NSWorkspace.shared.open(URL(string: "https://yen.chat")!)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(into: menu)
    }
}
