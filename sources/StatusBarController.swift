import AppKit
import Combine

/// Menu bar status item with wallpaper controls.
/// Adapts menu structure based on wallpaper mode (all displays vs per display).
@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let wallpaperManager: WallpaperManager
    private let updater: MovingPaperUpdater
    private var cancellables = Set<AnyCancellable>()

    init(wallpaperManager: WallpaperManager, updater: MovingPaperUpdater) {
        self.wallpaperManager = wallpaperManager
        self.updater = updater

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let icon = MenuBarIcon.brandIcon()
            icon.accessibilityDescription = "MovingPaper"
            button.image = icon
        }
        self.statusItem = item

        rebuildMenu()

        // Rebuild menu when any relevant state changes (debounced, skip initial emissions)
        Publishers.MergeMany(
            wallpaperManager.$desktopFiles.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            wallpaperManager.$isPaused.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            wallpaperManager.$isMuted.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            wallpaperManager.$mode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            wallpaperManager.$activeSpaceIDs.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            wallpaperManager.youtubeDownloader.$state.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            updater.$canCheckForUpdates.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] in self?.rebuildMenu() }
        .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Show download progress if active
        if case .downloading(let progress) = wallpaperManager.youtubeDownloader.state {
            let pct = Int(progress * 100)
            let progressItem = NSMenuItem(title: "Downloading: \(pct)%...", action: nil, keyEquivalent: "")
            progressItem.isEnabled = false
            menu.addItem(progressItem)

            let cancelItem = NSMenuItem(
                title: "Cancel Download",
                action: #selector(cancelDownload),
                keyEquivalent: ""
            )
            cancelItem.target = self
            menu.addItem(cancelItem)
            menu.addItem(.separator())
        }

        switch wallpaperManager.mode {
        case .allDesktops:
            buildAllDesktopsMenu(menu)
        case .perDesktop:
            buildPerDesktopMenu(menu)
        }

        menu.addItem(.separator())

        // ── Sound toggle ──
        let soundTitle = wallpaperManager.isMuted ? "Sound: Off" : "Sound: On"
        let soundItem = NSMenuItem(
            title: soundTitle,
            action: #selector(toggleMute),
            keyEquivalent: "s"
        )
        soundItem.target = self
        if !wallpaperManager.isMuted {
            soundItem.state = .on
        }
        menu.addItem(soundItem)

        // ── Mode toggle ──
        let modeMenu = NSMenu()

        let allItem = NSMenuItem(
            title: "All Desktops",
            action: #selector(setModeAllDesktops),
            keyEquivalent: ""
        )
        allItem.target = self
        allItem.state = wallpaperManager.mode == .allDesktops ? .on : .off
        modeMenu.addItem(allItem)

        let perItem = NSMenuItem(
            title: "Per Desktop",
            action: #selector(setModePerDesktop),
            keyEquivalent: ""
        )
        perItem.target = self
        perItem.state = wallpaperManager.mode == .perDesktop ? .on : .off
        modeMenu.addItem(perItem)

        let modeItem = NSMenuItem(title: "MovingPaper Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(.separator())

        // ── Pause / Resume ──
        if wallpaperManager.hasAnyWallpaper {
            let pauseTitle = wallpaperManager.isPaused ? "Resume" : "Pause"
            let pauseKey = wallpaperManager.isPaused ? "r" : "p"
            let pauseItem = NSMenuItem(
                title: pauseTitle,
                action: #selector(togglePause),
                keyEquivalent: pauseKey
            )
            pauseItem.target = self
            menu.addItem(pauseItem)

            menu.addItem(.separator())
        }

        // ── Check for Updates ──
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let updateTitle = version.isEmpty ? "Check for Updates..." : "Check for Updates (v\(version))..."
        let updateItem = NSMenuItem(
            title: updateTitle,
            action: #selector(checkForUpdates),
            keyEquivalent: "u"
        )
        updateItem.target = self
        updateItem.isEnabled = updater.canCheckForUpdates
        menu.addItem(updateItem)

        // ── Built with YEN ──
        let yenItem = NSMenuItem(
            title: "Built with YEN",
            action: #selector(openYEN),
            keyEquivalent: ""
        )
        yenItem.target = self
        menu.addItem(yenItem)

        menu.addItem(.separator())

        // ── Quit ──
        let quitItem = NSMenuItem(
            title: "Quit MovingPaper",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - All Displays Mode Menu

    private func buildAllDesktopsMenu(_ menu: NSMenu) {
        if let url = wallpaperManager.sharedFileURL {
            let fileItem = NSMenuItem(
                title: MenuBarLabelFormatter.sharedWallpaperTitle(fileName: url.lastPathComponent),
                action: nil,
                keyEquivalent: ""
            )
            fileItem.isEnabled = false
            menu.addItem(fileItem)
            menu.addItem(.separator())

            let removeItem = NSMenuItem(
                title: "Remove MovingPaper",
                action: #selector(clearAllWallpapers),
                keyEquivalent: ""
            )
            removeItem.target = self
            menu.addItem(removeItem)

            menu.addItem(.separator())
        }

        let chooseItem = NSMenuItem(
            title: "Choose File...",
            action: #selector(chooseFileForAll),
            keyEquivalent: "o"
        )
        chooseItem.target = self
        menu.addItem(chooseItem)

        let youtubeItem = NSMenuItem(
            title: "Paste YouTube URL...",
            action: #selector(pasteYouTubeURLForAll),
            keyEquivalent: "y"
        )
        youtubeItem.target = self
        menu.addItem(youtubeItem)

        let photosItem = NSMenuItem(
            title: "Choose from Photos...",
            action: #selector(chooseFromPhotosForAll),
            keyEquivalent: ""
        )
        photosItem.target = self
        menu.addItem(photosItem)

        let shuffleItem = NSMenuItem(
            title: "Shuffle from Photos",
            action: #selector(shuffleFromPhotosForAll),
            keyEquivalent: ""
        )
        shuffleItem.target = self
        menu.addItem(shuffleItem)
    }

    // MARK: - Per Display Mode Menu

    private func buildPerDesktopMenu(_ menu: NSMenu) {
        let displays = wallpaperManager.connectedDisplays

        if displays.isEmpty {
            let noDisplays = NSMenuItem(title: "No Displays", action: nil, keyEquivalent: "")
            noDisplays.isEnabled = false
            menu.addItem(noDisplays)
            return
        }

        for (displayIndex, display) in displays.enumerated() {
            // Show display name only if multiple monitors
            if displays.count > 1 {
                let displayHeader = NSMenuItem(
                    title: MenuBarLabelFormatter.displayHeaderTitle(display.name),
                    action: nil,
                    keyEquivalent: ""
                )
                displayHeader.isEnabled = false
                menu.addItem(displayHeader)
            }

            let spaces = wallpaperManager.spaceAssignments(for: display.id)

            for (index, space) in spaces.enumerated() {
                let hasWallpaper = space.fileName != "No MovingPaper"
                let label = MenuBarLabelFormatter.desktopWallpaperTitle(
                    index: index + 1,
                    fileName: space.fileName
                )
                let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
                if space.isCurrent {
                    item.state = .on
                }

                let sub = NSMenu()
                if space.isCurrent {
                    buildDisplaySubmenu(sub, displayID: display.id, includeRemove: hasWallpaper)
                } else {
                    let info = NSMenuItem(title: "Switch to this desktop to change", action: nil, keyEquivalent: "")
                    info.isEnabled = false
                    sub.addItem(info)
                }
                item.submenu = sub
                menu.addItem(item)
            }

            if displayIndex < displays.count - 1 {
                menu.addItem(.separator())
            }
        }

        if wallpaperManager.hasAnyWallpaper {
            menu.addItem(.separator())
            let clearAllItem = NSMenuItem(
                title: "Remove All MovingPapers",
                action: #selector(clearAllWallpapers),
                keyEquivalent: ""
            )
            clearAllItem.target = self
            menu.addItem(clearAllItem)
        }
    }

    // MARK: - Submenu Builder

    private func buildDisplaySubmenu(_ menu: NSMenu, displayID: CGDirectDisplayID, includeRemove: Bool) {
        let tag = Int(displayID)
        for (title, action) in [
            ("Choose File...", #selector(chooseFileForDisplay(_:))),
            ("Paste YouTube URL...", #selector(pasteYouTubeURLForDisplay(_:))),
            ("Choose from Photos...", #selector(chooseFromPhotosForDisplay(_:))),
            ("Shuffle from Photos", #selector(shuffleFromPhotosForDisplay(_:))),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = tag
            menu.addItem(item)
        }
        if includeRemove {
            let item = NSMenuItem(title: "Remove", action: #selector(clearDisplayWallpaper(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            menu.addItem(item)
        }
    }

    // MARK: - Actions

    @objc private func chooseFileForAll() {
        wallpaperManager.selectFile()
    }

    @objc private func chooseFileForDisplay(_ sender: NSMenuItem) {
        let displayID = CGDirectDisplayID(sender.tag)
        wallpaperManager.selectFile(for: displayID)
    }

    @objc private func clearDisplayWallpaper(_ sender: NSMenuItem) {
        let displayID = CGDirectDisplayID(sender.tag)
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

    @objc private func pasteYouTubeURLForAll() {
        let urlString = promptForYouTubeURL()
        guard let urlString else { return }
        wallpaperManager.setYouTubeWallpaper(urlString: urlString)
    }

    @objc private func pasteYouTubeURLForDisplay(_ sender: NSMenuItem) {
        let urlString = promptForYouTubeURL()
        guard let urlString else { return }
        let displayID = CGDirectDisplayID(sender.tag)
        wallpaperManager.setYouTubeWallpaper(urlString: urlString, for: displayID)
    }

    @objc private func cancelDownload() {
        wallpaperManager.youtubeDownloader.cancel()
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

    @objc private func chooseFromPhotosForAll() {
        AppPresentation.promoteToForeground()
        Task {
            defer { AppPresentation.returnToAccessory() }
            let picker = PhotosPickerController()
            let url = await picker.run()
            guard let url else { return }
            wallpaperManager.setWallpaper(url: url)
        }
    }

    @objc private func chooseFromPhotosForDisplay(_ sender: NSMenuItem) {
        let displayID = CGDirectDisplayID(sender.tag)
        AppPresentation.promoteToForeground()
        Task {
            defer { AppPresentation.returnToAccessory() }
            let picker = PhotosPickerController()
            let url = await picker.run()
            guard let url else { return }
            wallpaperManager.setWallpaper(url: url, for: displayID)
        }
    }

    @objc private func shuffleFromPhotosForAll() {
        wallpaperManager.shuffleFromPhotos()
    }

    @objc private func shuffleFromPhotosForDisplay(_ sender: NSMenuItem) {
        let displayID = CGDirectDisplayID(sender.tag)
        wallpaperManager.shuffleFromPhotos(for: displayID)
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
