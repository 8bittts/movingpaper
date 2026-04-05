import AppKit
import Combine

/// How wallpapers are assigned.
enum WallpaperMode: String {
    case allDesktops   // one file across all screens and spaces
    case perDesktop    // different file per screen + space (like native macOS)
}

/// Composite key for per-desktop wallpaper assignments.
/// Combines physical display + macOS Space for unique identification.
struct DesktopKey: Hashable {
    let displayID: CGDirectDisplayID
    let spaceID: UInt64

    /// Key for "all desktops" mode — space is irrelevant.
    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        self.spaceID = 0
    }

    init(displayID: CGDirectDisplayID, spaceID: UInt64) {
        self.displayID = displayID
        self.spaceID = spaceID
    }
}

// MARK: - Space Detection (CoreGraphics private, stable since 10.6)

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> UInt32

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: UInt32) -> UInt64

/// Returns the active macOS Space ID for the current desktop.
func currentSpaceID() -> UInt64 {
    CGSGetActiveSpace(CGSMainConnectionID())
}

/// Central coordinator: manages per-screen wallpaper windows, file selection,
/// playback state, sound, space tracking, and power-aware pause/resume.
@MainActor
final class WallpaperManager: ObservableObject {

    // MARK: - Published State

    /// Per-desktop file assignments. Key combines display + space.
    @Published var desktopFiles: [DesktopKey: URL] = [:]

    /// Whether all desktops share one wallpaper or each gets its own.
    @Published var mode: WallpaperMode = .allDesktops

    /// User-initiated pause (distinct from system pause).
    @Published var isPaused: Bool = false

    /// Whether video audio is muted.
    @Published var isMuted: Bool = true

    /// YouTube downloader for pasting YouTube URLs as wallpapers.
    let youtubeDownloader = YouTubeDownloader()

    // MARK: - Private State

    private var controllers: [CGDirectDisplayID: WallpaperWindowController] = [:]
    private var screenObserver: Any?
    private var spaceObserver: Any?
    private var powerObservers: [Any] = []
    private var systemPaused: Bool = false
    @Published private(set) var activeSpaceID: UInt64 = 0

    /// Original YouTube URLs for desktops using YouTube content (for re-download if cache cleared).
    private var youtubeURLs: [DesktopKey: String] = [:]

    // MARK: - Persistence Keys

    private enum Defaults {
        static let desktopFiles = "desktopFiles"
        static let mode = "wallpaperMode"
        static let isMuted = "isMuted"
    }

    init() {
        activeSpaceID = currentSpaceID()
        restoreState()
        observeScreenChanges()
        observeSpaceChanges()
        observePowerState()
    }

    // MARK: - Computed Helpers

    /// In allDesktops mode, returns the single shared file URL (if any).
    var sharedFileURL: URL? {
        guard mode == .allDesktops else { return nil }
        return desktopFiles.values.first
    }

    /// File name for a display on the current space.
    func fileName(for displayID: CGDirectDisplayID) -> String? {
        fileURL(for: displayID)?.lastPathComponent
    }

    /// File URL for a display, respecting the current mode and space.
    func fileURL(for displayID: CGDirectDisplayID) -> URL? {
        switch mode {
        case .allDesktops:
            return desktopFiles[DesktopKey(displayID: displayID)]
        case .perDesktop:
            return desktopFiles[DesktopKey(displayID: displayID, spaceID: activeSpaceID)]
        }
    }

    /// Determine file type from URL extension.
    func fileType(for url: URL) -> WallpaperFileType? {
        switch url.pathExtension.lowercased() {
        case "gif":            return .gif
        case "mov", "mp4", "m4v": return .video
        default:               return nil
        }
    }

    /// All connected displays.
    var connectedDisplays: [(id: CGDirectDisplayID, name: String)] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return (id: id, name: screen.localizedName)
        }
    }

    /// All Spaces with wallpapers assigned for a given display, sorted by space ID.
    /// Returns (spaceID, fileName, isCurrent) tuples.
    func spaceAssignments(for displayID: CGDirectDisplayID) -> [(spaceID: UInt64, fileName: String, isCurrent: Bool)] {
        desktopFiles
            .filter { $0.key.displayID == displayID && $0.key.spaceID != 0 }
            .map { (spaceID: $0.key.spaceID, fileName: $0.value.lastPathComponent, isCurrent: $0.key.spaceID == activeSpaceID) }
            .sorted { $0.spaceID < $1.spaceID }
    }

    /// Whether any desktop has a wallpaper assigned.
    var hasAnyWallpaper: Bool {
        !desktopFiles.isEmpty
    }

    /// Whether the current space has any wallpaper on any display.
    var currentSpaceHasWallpaper: Bool {
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            if fileURL(for: id) != nil { return true }
        }
        return false
    }

    // MARK: - File Selection

    /// Open file picker and assign result.
    func selectFile(for displayID: CGDirectDisplayID? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .gif, .mpeg4Movie, .quickTimeMovie, .movie,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a GIF or video file for your Moving Paper wallpaper"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setWallpaper(url: url, for: displayID)
    }

    /// Assign a wallpaper file.
    func setWallpaper(url: URL, for displayID: CGDirectDisplayID? = nil) {
        isPaused = false

        switch mode {
        case .allDesktops:
            desktopFiles.removeAll()
            for screen in NSScreen.screens {
                if let id = screen.displayID {
                    desktopFiles[DesktopKey(displayID: id)] = url
                }
            }
        case .perDesktop:
            if let id = displayID {
                let key = DesktopKey(displayID: id, spaceID: activeSpaceID)
                desktopFiles[key] = url
            }
        }

        saveState()
        rebuildAllWindows()
    }

    /// Download a YouTube video and set it as wallpaper.
    func setYouTubeWallpaper(urlString: String, for displayID: CGDirectDisplayID? = nil) {
        guard YouTubeURLParser.isYouTubeURL(urlString) else {
            showAlert(title: "Invalid URL", message: "That doesn't look like a YouTube URL.")
            return
        }

        Task {
            guard let localURL = await youtubeDownloader.download(youtubeURL: urlString) else {
                if case .failed(let msg) = youtubeDownloader.state {
                    showAlert(title: "Download Failed", message: msg)
                }
                return
            }

            // Store the YouTube URL for persistence
            switch mode {
            case .allDesktops:
                youtubeURLs.removeAll()
                for screen in NSScreen.screens {
                    if let id = screen.displayID {
                        youtubeURLs[DesktopKey(displayID: id)] = urlString
                    }
                }
            case .perDesktop:
                if let id = displayID {
                    youtubeURLs[DesktopKey(displayID: id, spaceID: activeSpaceID)] = urlString
                }
            }

            setWallpaper(url: localURL, for: displayID)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Remove wallpaper from a specific display (current space in perDesktop mode).
    func clearWallpaper(for displayID: CGDirectDisplayID) {
        switch mode {
        case .allDesktops:
            let key = DesktopKey(displayID: displayID)
            desktopFiles.removeValue(forKey: key)
            youtubeURLs.removeValue(forKey: key)
        case .perDesktop:
            let key = DesktopKey(displayID: displayID, spaceID: activeSpaceID)
            desktopFiles.removeValue(forKey: key)
            youtubeURLs.removeValue(forKey: key)
        }
        if let controller = controllers.removeValue(forKey: displayID) {
            controller.close()
        }
        saveState()
    }

    /// Remove all wallpapers.
    func clearAllWallpapers() {
        desktopFiles.removeAll()
        youtubeURLs.removeAll()
        tearDownWindows()
        saveState()
    }

    /// Switch modes.
    func setMode(_ newMode: WallpaperMode) {
        guard newMode != mode else { return }

        if newMode == .allDesktops, let firstURL = desktopFiles.values.first {
            let firstYT = youtubeURLs.values.first
            desktopFiles.removeAll()
            youtubeURLs.removeAll()
            for screen in NSScreen.screens {
                if let id = screen.displayID {
                    let key = DesktopKey(displayID: id)
                    desktopFiles[key] = firstURL
                    if let yt = firstYT { youtubeURLs[key] = yt }
                }
            }
        } else if newMode == .perDesktop {
            let oldFiles = desktopFiles
            let oldYT = youtubeURLs
            desktopFiles.removeAll()
            youtubeURLs.removeAll()
            for (key, url) in oldFiles {
                let newKey = DesktopKey(displayID: key.displayID, spaceID: activeSpaceID)
                desktopFiles[newKey] = url
                if let yt = oldYT[key] { youtubeURLs[newKey] = yt }
            }
        }

        mode = newMode
        saveState()
        rebuildAllWindows()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            tearDownWindows()
        } else {
            rebuildAllWindows()
        }
    }

    func toggleMute() {
        isMuted.toggle()
        saveState()
        rebuildAllWindows()
    }

    // MARK: - Persistence

    private func saveState() {
        let encoded: [[String: Any]] = desktopFiles.map { (key, url) in
            var entry: [String: Any] = [
                "displayID": NSNumber(value: key.displayID),
                "spaceID": NSNumber(value: key.spaceID),
                "path": url.path(percentEncoded: false),
            ]
            if let ytURL = youtubeURLs[key] {
                entry["youtubeURL"] = ytURL
            }
            return entry
        }
        UserDefaults.standard.set(encoded, forKey: Defaults.desktopFiles)
        UserDefaults.standard.set(mode.rawValue, forKey: Defaults.mode)
        UserDefaults.standard.set(isMuted, forKey: Defaults.isMuted)
    }

    private func restoreState() {
        if let raw = UserDefaults.standard.string(forKey: Defaults.mode),
           let savedMode = WallpaperMode(rawValue: raw) {
            mode = savedMode
        }
        isMuted = UserDefaults.standard.object(forKey: Defaults.isMuted) as? Bool ?? true

        guard let entries = UserDefaults.standard.array(forKey: Defaults.desktopFiles)
                as? [[String: Any]] else { return }

        var needsRedownload: [(DesktopKey, String)] = []

        for entry in entries {
            guard let displayIDNum = entry["displayID"] as? NSNumber,
                  let spaceIDNum = entry["spaceID"] as? NSNumber,
                  let path = entry["path"] as? String else { continue }
            let key = DesktopKey(
                displayID: displayIDNum.uint32Value,
                spaceID: spaceIDNum.uint64Value
            )

            // Restore YouTube URL mapping
            if let ytURL = entry["youtubeURL"] as? String {
                youtubeURLs[key] = ytURL
            }

            if FileManager.default.fileExists(atPath: path) {
                desktopFiles[key] = URL(filePath: path)
            } else if let ytURL = entry["youtubeURL"] as? String {
                // File missing but we have the YouTube URL — queue re-download
                needsRedownload.append((key, ytURL))
            }
        }

        if !desktopFiles.isEmpty {
            rebuildAllWindows()
        }

        // Re-download missing YouTube videos in background
        for (key, ytURL) in needsRedownload {
            Task {
                guard let localURL = await youtubeDownloader.download(youtubeURL: ytURL) else { return }
                desktopFiles[key] = localURL
                saveState()
                rebuildAllWindows()
            }
        }
    }

    // MARK: - Window Lifecycle

    func rebuildAllWindows() {
        tearDownWindows()
        guard !isPaused else { return }

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            guard let url = fileURL(for: displayID) else { continue }
            guard let type = fileType(for: url) else { continue }

            let controller = WallpaperWindowController(screen: screen)

            switch type {
            case .video:
                controller.show(content: VideoWallpaperView(url: url, isMuted: isMuted))
            case .gif:
                controller.show(content: GIFWallpaperView(url: url))
            }

            controllers[displayID] = controller
        }
    }

    func tearDown() {
        tearDownWindows()
        removeScreenObserver()
        removeSpaceObserver()
        for observer in powerObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        powerObservers.removeAll()
    }

    private func tearDownWindows() {
        for controller in controllers.values {
            controller.close()
        }
        controllers.removeAll()
    }

    // MARK: - Screen Changes

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                if self.mode == .allDesktops, let url = self.sharedFileURL {
                    for screen in NSScreen.screens {
                        if let id = screen.displayID {
                            let key = DesktopKey(displayID: id)
                            if self.desktopFiles[key] == nil {
                                self.desktopFiles[key] = url
                            }
                        }
                    }
                }

                self.rebuildAllWindows()
            }
        }
    }

    private func removeScreenObserver() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }

    // MARK: - Space Changes

    private func observeSpaceChanges() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.activeSpaceID = currentSpaceID()
                self.rebuildAllWindows()
            }
        }
    }

    private func removeSpaceObserver() {
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            spaceObserver = nil
        }
    }

    // MARK: - Power Management

    private func observePowerState() {
        let lowPower = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.evaluatePowerState() }
        }
        powerObservers.append(lowPower)

        let thermal = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.evaluatePowerState() }
        }
        powerObservers.append(thermal)
    }

    private func evaluatePowerState() {
        let shouldPause =
            ProcessInfo.processInfo.isLowPowerModeEnabled
            || ProcessInfo.processInfo.thermalState == .serious
            || ProcessInfo.processInfo.thermalState == .critical

        if shouldPause && !systemPaused {
            systemPaused = true
            tearDownWindows()
        } else if !shouldPause && systemPaused {
            systemPaused = false
            if !isPaused {
                rebuildAllWindows()
            }
        }
    }

}

// MARK: - Helpers

enum WallpaperFileType {
    case gif
    case video
}

extension NSScreen {
    /// Stable display ID for this screen.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
