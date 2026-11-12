import AppKit

/// Menu bar status item with wallpaper controls. Rebuilds its menu on demand
/// (via NSMenuDelegate.menuNeedsUpdate) so per-state-change Combine pipelines
/// don't throw NSMenuItems away dozens of times per second during typing or
/// download-progress updates.
@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let wallpaperManager: WallpaperManager
    private let updater: MovingPaperUpdater
    private var isPickingFromPhotos = false

    init(wallpaperManager: WallpaperManager, updater: MovingPaperUpdater) {
        self.wallpaperManager = wallpaperManager
        self.updater = updater
        super.init()

        statusItem.button?.image = MenuBarIcon.brandIcon()
        statusItem.button?.toolTip = "MovingPaper"
        let menu = makeMenu([])
        menu.delegate = self
        statusItem.menu = menu
    }

    private var menuInput: MenuModelInput {
        wallpaperManager.menuInput(
            canCheckForUpdates: updater.canCheckForUpdates,
            loginItem: OpenAtLogin.status
        )
    }

    private func rebuildMenu(into menu: NSMenu) {
        menu.removeAllItems()
        append(MenuSnapshot.rows(from: menuInput), to: menu)
    }

    // MARK: - Reopen and Dock Fallback

    /// The app was opened while it runs. The system hides menu bar extras when
    /// the menu bar runs out of room, and `NSStatusItem.isVisible` still reads
    /// true then, so the app cannot tell whether the user can see its icon.
    /// The first reopen starts a Dock session: a Dock icon whose menu carries
    /// the same commands. A reopen during the session (a click on that Dock
    /// icon) shows the menu at the pointer.
    func handleReopen() {
        statusItem.isVisible = true
        if AppPresentation.isHeld(.dockSession) {
            NSApp.activate()
            makeMenu(MenuSnapshot.rows(from: menuInput))
                .popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        } else {
            AppPresentation.begin(.dockSession)
        }
    }

    /// The Dock icon's menu. The Dock adds its own Quit item.
    func makeDockMenu() -> NSMenu {
        makeMenu(MenuSnapshot.dockRows(from: menuInput))
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
        case .submenu(let title, let checked, let rows):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.state = checked ? .on : .off
            item.submenu = makeMenu(rows)
            return item
        }
    }

    private func makeMenu(_ rows: [MenuRow]) -> NSMenu {
        let menu = NSMenu()
        // Manage enabled state ourselves; otherwise AppKit auto-enables any item
        // with a valid target/action, overriding e.g. the Check-for-Updates gate.
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
        if let symbolName = command.symbolName {
            // Decorative: the title already names the action for VoiceOver.
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
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
        case .about: #selector(about)
        case .toggleOpenAtLogin: #selector(toggleOpenAtLogin)
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
        guard let urlString = promptForYouTubeURL() else { return }
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
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
            input.placeholderString = "https://youtube.com/watch?v=..."
            // A pasted clipboard value hides the placeholder, so the field needs its own name.
            input.setAccessibilityLabel("YouTube URL")
            input.lineBreakMode = .byTruncatingMiddle
            input.usesSingleLineMode = true
            // Prefill only a YouTube URL: any other clipboard text is not what
            // this field is for and may be something private.
            if let clip = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               YouTubeURLParser.isYouTubeURL(clip) {
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
    /// One picker at a time: a second request while one is open does nothing.
    private func presentPhotosPicker(for displayID: CGDirectDisplayID?) {
        guard !isPickingFromPhotos else { return }
        isPickingFromPhotos = true
        AppPresentation.begin(.photosPicker)
        Task {
            defer {
                isPickingFromPhotos = false
                AppPresentation.end(.photosPicker)
            }
            guard let url = await PhotosPickerController().run() else { return }
            wallpaperManager.setWallpaper(url: url, for: displayID)
        }
    }

    @objc private func shufflePhotos(_ sender: NSMenuItem) {
        wallpaperManager.shuffleFromPhotos(for: optionalDisplayID(sender))
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func about() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        // HIG: About shows "copyright and version information".
        let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
        AppPresentation.withForegroundActivation {
            let alert = NSAlert()
            alert.messageText = "MovingPaper"
            let versionLine = version.isEmpty ? "" : "Version \(version)\n\n"
            let copyrightLine = copyright.isEmpty ? "" : "\n\n\(copyright)"
            alert.informativeText = "\(versionLine)A moving wallpaper for your desktop.\n\nBuilt with YEN — yen.chat\(copyrightLine)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Visit YEN")
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.open(URL(string: "https://yen.chat")!)
            }
        }
    }

    @objc private func toggleOpenAtLogin() {
        do {
            try OpenAtLogin.toggle()
        } catch {
            AppPresentation.showAlert(
                title: "Couldn't Update Login Item",
                message: error.localizedDescription,
                style: .warning
            )
        }
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

    /// The status menu opened, so the user can reach the menu-bar extra and the
    /// Dock fallback has done its job.
    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusItem.menu, AppPresentation.isHeld(.dockSession) else { return }
        AppPresentation.end(.dockSession)
    }
}
