import AppKit
import AVFoundation
import Combine
import SwiftUI

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

    /// Photos library access for shuffle mode.
    let photosService = PhotosService()

    // MARK: - Private State

    private var controllers: [CGDirectDisplayID: WallpaperWindowController] = [:]
    private var screenObserver: Any?
    private var spaceObserver: Any?
    private var powerObservers: [Any] = []
    private var systemPaused: Bool = false
    private let loadingOverlay = LoadingOverlayController()
    private var downloadOverlayObserver: AnyCancellable?
    @Published private(set) var activeSpaceID: UInt64 = 0
    /// All Space IDs we've seen on each display (macOS has no API to enumerate Spaces).
    private var knownSpaces: [CGDirectDisplayID: Set<UInt64>] = [:]

    private var youtubeURLs: [DesktopKey: String] = [:]
    /// Cached playback positions so videos resume where the user left off after space switches.
    private var playbackPositions: [DesktopKey: CMTime] = [:]

    // MARK: - Persistence Keys

    private enum Defaults {
        static let desktopFiles = "desktopFiles"
        static let mode = "wallpaperMode"
        static let isMuted = "isMuted"
    }

    init() {
        activeSpaceID = currentSpaceID()
        trackCurrentSpace()
        restoreState()
        observeScreenChanges()
        observeSpaceChanges()
        observePowerState()
        observeDownloadState()
    }

    private func trackCurrentSpace() {
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            knownSpaces[id, default: []].insert(activeSpaceID)
        }
    }

    // MARK: - Computed Helpers

    /// In allDesktops mode, returns the single shared file URL (if any).
    var sharedFileURL: URL? {
        guard mode == .allDesktops else { return nil }
        return desktopFiles.values.first
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

    /// All known Spaces for a display, sorted by space ID.
    /// Includes Spaces with and without wallpapers — we track every Space the user visits.
    func spaceAssignments(for displayID: CGDirectDisplayID) -> [(spaceID: UInt64, fileName: String, isCurrent: Bool)] {
        let spaces = knownSpaces[displayID] ?? []
        return spaces.sorted().map { spaceID in
            let key = DesktopKey(displayID: displayID, spaceID: spaceID)
            let fileName = desktopFiles[key]?.lastPathComponent ?? "No MovingPaper"
            return (spaceID: spaceID, fileName: fileName, isCurrent: spaceID == activeSpaceID)
        }
    }

    /// Whether any desktop has a wallpaper assigned.
    var hasAnyWallpaper: Bool {
        !desktopFiles.isEmpty
    }

    // MARK: - File Selection

    /// Open file picker and assign result.
    func selectFile(for displayID: CGDirectDisplayID? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        defer { NSApp.setActivationPolicy(.accessory) }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .gif, .mpeg4Movie, .quickTimeMovie, .movie,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a GIF or video file for your MovingPaper wallpaper"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setWallpaper(url: url, for: displayID)
    }

    /// Assign a wallpaper file. In perDesktop mode, `spaceID` pins to a specific
    /// space (use when the result arrives async and the user may have switched spaces).
    func setWallpaper(url: URL, for displayID: CGDirectDisplayID? = nil, spaceID: UInt64? = nil) {
        isPaused = false

        switch mode {
        case .allDesktops:
            desktopFiles.removeAll()
            youtubeURLs.removeAll()
            for screen in NSScreen.screens {
                if let id = screen.displayID {
                    desktopFiles[DesktopKey(displayID: id)] = url
                }
            }
        case .perDesktop:
            if let id = displayID {
                let space = spaceID ?? activeSpaceID
                let key = DesktopKey(displayID: id, spaceID: space)
                desktopFiles[key] = url
                youtubeURLs.removeValue(forKey: key)
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

        let originSpaceID = activeSpaceID
        Task {
            guard let localURL = await youtubeDownloader.download(youtubeURL: urlString) else {
                if case .failed(let msg) = youtubeDownloader.state {
                    showAlert(title: "Download Failed", message: msg)
                }
                return
            }

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
                    youtubeURLs[DesktopKey(displayID: id, spaceID: originSpaceID)] = urlString
                }
            }

            setWallpaper(url: localURL, for: displayID, spaceID: originSpaceID)
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

    // MARK: - Photos Shuffle

    /// Pick a random video from the entire Photos library and set it as wallpaper.
    func shuffleFromPhotos(for displayID: CGDirectDisplayID? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        loadingOverlay.show(message: "Shuffling...")
        let originSpaceID = activeSpaceID
        Task {
            guard let url = await photosService.randomVideoURL() else {
                loadingOverlay.hide()
                NSApp.setActivationPolicy(.accessory)
                showAlert(title: "No Videos Found", message: "Grant Photos access in System Settings or add videos to your library.")
                return
            }
            loadingOverlay.hide()
            NSApp.setActivationPolicy(.accessory)
            setWallpaper(url: url, for: displayID, spaceID: originSpaceID)
        }
    }

    /// The DesktopKey for a display on the current space, respecting mode.
    private func desktopKey(for displayID: CGDirectDisplayID) -> DesktopKey {
        switch mode {
        case .allDesktops:
            return DesktopKey(displayID: displayID)
        case .perDesktop:
            return DesktopKey(displayID: displayID, spaceID: activeSpaceID)
        }
    }

    /// Remove wallpaper from a specific display (current space in perDesktop mode).
    func clearWallpaper(for displayID: CGDirectDisplayID) {
        let key = desktopKey(for: displayID)
        desktopFiles.removeValue(forKey: key)
        youtubeURLs.removeValue(forKey: key)
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

        if newMode == .allDesktops {
            if let firstURL = desktopFiles.values.first {
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
        for controller in controllers.values {
            controller.player?.isMuted = isMuted
        }
    }

    // MARK: - Loading Overlay

    private func observeDownloadState() {
        downloadOverlayObserver = youtubeDownloader.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .downloading(let progress):
                    let pct = Int(progress * 100)
                    self.loadingOverlay.show(message: "Downloading \(pct)%", progress: progress)
                case .idle, .failed:
                    self.loadingOverlay.hide()
                }
            }
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

            // Track this space so it appears in the per-desktop menu
            if key.spaceID != 0 {
                knownSpaces[key.displayID, default: []].insert(key.spaceID)
            }

            if FileManager.default.fileExists(atPath: path) {
                desktopFiles[key] = URL(filePath: path)
            } else if let ytURL = entry["youtubeURL"] as? String {
                // File missing but we have the YouTube URL — queue re-download
                needsRedownload.append((key, ytURL))
            }
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

        if !desktopFiles.isEmpty {
            rebuildAllWindows()
        }
    }

    // MARK: - Window Lifecycle

    func rebuildAllWindows() {
        guard !isPaused else {
            tearDownWindows()
            return
        }

        var activeDisplays = Set<CGDirectDisplayID>()

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            activeDisplays.insert(displayID)

            guard let url = fileURL(for: displayID),
                  let type = fileType(for: url) else {
                if let controller = controllers.removeValue(forKey: displayID) {
                    controller.close()
                }
                continue
            }

            if let existing = controllers[displayID] {
                if existing.currentURL == url {
                    existing.reposition(to: screen)
                    continue
                }
                existing.close()
            }

            let controller = WallpaperWindowController(screen: screen)
            switch type {
            case .video:
                let view = VideoWallpaperView(url: url, isMuted: isMuted)
                controller.show(content: view, url: url)
                let key = desktopKey(for: displayID)
                let resume = playbackPositions[key]
                // Grab player reference and seek after the video has started loading.
                // Two-stage: async to let SwiftUI create the NSView, then 0.3s for
                // AVPlayerLooper to finish setup and the item to begin playback.
                DispatchQueue.main.async { [weak controller] in
                    guard let controller else { return }
                    if let videoView = Self.findVideoView(in: controller.panel.contentView) {
                        controller.player = videoView.player
                    }
                    guard let resume, resume.isValid, resume.seconds > 0.1 else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak controller] in
                        controller?.player?.seek(to: resume, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                }
            case .gif:
                controller.show(content: GIFWallpaperView(url: url), url: url)
            }
            controllers[displayID] = controller
        }

        for displayID in controllers.keys where !activeDisplays.contains(displayID) {
            controllers.removeValue(forKey: displayID)?.close()
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
        savePlaybackPositions()
        for controller in controllers.values {
            controller.close()
        }
        controllers.removeAll()
    }

    private static func findVideoView(in view: NSView?) -> VideoPlayerNSView? {
        guard let view else { return nil }
        if let v = view as? VideoPlayerNSView { return v }
        for sub in view.subviews {
            if let found = findVideoView(in: sub) { return found }
        }
        return nil
    }

    private func savePlaybackPositions() {
        for (displayID, controller) in controllers {
            guard controller.currentURL != nil else { continue }
            let key = desktopKey(for: displayID)
            if let time = controller.player?.currentTime(), time.isValid, time.seconds > 0 {
                playbackPositions[key] = time
            }
        }
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
                self.savePlaybackPositions()
                self.activeSpaceID = currentSpaceID()
                self.trackCurrentSpace()
                if self.mode == .allDesktops {
                    // Panels have .canJoinAllSpaces — no rebuild needed
                    return
                }
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
