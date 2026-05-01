import AppKit
import AVFoundation
import Combine
import SwiftUI

/// Central coordinator: manages per-screen wallpaper windows, file selection,
/// playback state, sound, space tracking, and power-aware pause/resume.
@MainActor
final class WallpaperManager: ObservableObject {

    private enum ActiveDownloadSource: Equatable {
        case assignment(WallpaperAssignmentTarget)
        case restore
    }

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
    private let requestCoordinator = WallpaperRequestCoordinator()
    private let persistenceStore = WallpaperPersistenceStore()
    private var restoreTask: Task<Void, Never>?
    private var activeDownloadSource: ActiveDownloadSource?
    @Published private(set) var activeSpaceIDs: [CGDirectDisplayID: UInt64] = [:]
    /// All Space IDs we've seen on each display (macOS has no API to enumerate Spaces).
    private var knownSpaces: [CGDirectDisplayID: Set<UInt64>] = [:]

    private var youtubeURLs: [DesktopKey: String] = [:]
    /// Cached playback positions so videos resume where the user left off after space switches.
    private var playbackPositions: [DesktopKey: CMTime] = [:]

    init() {
        refreshManagedDisplaySpaces()
        restoreState()
        observeScreenChanges()
        observeSpaceChanges()
        observePowerState()
        observeDownloadState()
    }

    private func refreshManagedDisplaySpaces() {
        let snapshot = ManagedDisplaySpacesSnapshot.current()
        activeSpaceIDs = snapshot.activeSpaceByDisplayID

        for (displayID, spaces) in snapshot.knownSpacesByDisplayID {
            knownSpaces[displayID, default: []].formUnion(spaces)
        }
    }

    private func currentSpaceID(for displayID: CGDirectDisplayID) -> UInt64 {
        activeSpaceIDs[displayID] ?? currentGlobalSpaceID()
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
            return desktopFiles[DesktopKey(displayID: displayID, spaceID: currentSpaceID(for: displayID))]
        }
    }

    /// Determine file type from URL extension.
    func fileType(for url: URL) -> WallpaperFileType? {
        WallpaperFileType.detect(for: url)
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
        let currentSpace = currentSpaceID(for: displayID)
        return spaces.sorted().map { spaceID in
            let key = DesktopKey(displayID: displayID, spaceID: spaceID)
            let fileName = desktopFiles[key]?.lastPathComponent ?? "No MovingPaper"
            return (spaceID: spaceID, fileName: fileName, isCurrent: spaceID == currentSpace)
        }
    }

    /// Whether any desktop has a wallpaper assigned.
    var hasAnyWallpaper: Bool {
        !desktopFiles.isEmpty
    }

    // MARK: - File Selection

    private func assignmentTarget(for displayID: CGDirectDisplayID?) -> WallpaperAssignmentTarget {
        if let displayID {
            return .display(displayID)
        }
        return .allDesktops
    }

    private func cancelRestoreTask() {
        restoreTask?.cancel()
        restoreTask = nil
        if activeDownloadSource == .restore {
            youtubeDownloader.cancel()
            activeDownloadSource = nil
        }
    }

    private func cancelAssignment(for target: WallpaperAssignmentTarget) {
        requestCoordinator.cancel(target)
        if activeDownloadSource == .assignment(target) {
            youtubeDownloader.cancel()
            activeDownloadSource = nil
        }
        loadingOverlay.hide()
        AppPresentation.returnToAccessory()
    }

    private func cancelAllAssignments() {
        requestCoordinator.cancelAll()
        if case .assignment = activeDownloadSource {
            youtubeDownloader.cancel()
            activeDownloadSource = nil
        }
        loadingOverlay.hide()
        AppPresentation.returnToAccessory()
    }

    /// Open file picker and assign result.
    func selectFile(for displayID: CGDirectDisplayID? = nil) {
        AppPresentation.withForegroundActivation {
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
    }

    /// Assign a wallpaper file. In perDesktop mode, `spaceID` pins to a specific
    /// space (use when the result arrives async and the user may have switched spaces).
    func setWallpaper(url: URL, for displayID: CGDirectDisplayID? = nil) {
        cancelAssignment(for: assignmentTarget(for: displayID))
        cancelRestoreTask()
        applyWallpaper(url: url, for: displayID)
    }

    private func applyWallpaper(url: URL, for displayID: CGDirectDisplayID? = nil, spaceID: UInt64? = nil) {
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
                let space = spaceID ?? currentSpaceID(for: id)
                let key = DesktopKey(displayID: id, spaceID: space)
                desktopFiles[key] = url
                youtubeURLs.removeValue(forKey: key)
                knownSpaces[id, default: []].insert(space)
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

        let target = assignmentTarget(for: displayID)
        let originSpaceID = displayID.map { currentSpaceID(for: $0) } ?? 0
        cancelRestoreTask()
        requestCoordinator.start(for: target) { [weak self] token in
            guard let self else { return }
            activeDownloadSource = .assignment(target)
            defer {
                if activeDownloadSource == .assignment(target) {
                    activeDownloadSource = nil
                }
            }
            guard let localURL = await youtubeDownloader.download(youtubeURL: urlString) else {
                guard requestCoordinator.isCurrent(token, for: target) else { return }
                if case .failed(let msg) = youtubeDownloader.state {
                    showAlert(title: "Download Failed", message: msg)
                }
                return
            }
            guard requestCoordinator.isCurrent(token, for: target) else { return }

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
                    knownSpaces[id, default: []].insert(originSpaceID)
                }
            }

            applyWallpaper(url: localURL, for: displayID, spaceID: originSpaceID)
        }
    }

    private func showAlert(title: String, message: String) {
        AppPresentation.showWarningAlert(title: title, message: message)
    }

    // MARK: - Photos Shuffle

    /// Pick a random video from the entire Photos library and set it as wallpaper.
    func shuffleFromPhotos(for displayID: CGDirectDisplayID? = nil) {
        AppPresentation.promoteToForeground()
        let target = assignmentTarget(for: displayID)
        let originSpaceID = displayID.map { currentSpaceID(for: $0) } ?? 0
        cancelRestoreTask()
        requestCoordinator.start(for: target) { [weak self] token in
            guard let self else { return }
            loadingOverlay.show(message: "Shuffling...")
            guard let url = await photosService.randomVideoURL() else {
                guard requestCoordinator.isCurrent(token, for: target) else { return }
                loadingOverlay.hide()
                AppPresentation.returnToAccessory()
                showAlert(title: "No Videos Found", message: "Grant Photos access in System Settings or add videos to your library.")
                return
            }
            guard requestCoordinator.isCurrent(token, for: target) else { return }
            loadingOverlay.hide()
            AppPresentation.returnToAccessory()
            applyWallpaper(url: url, for: displayID, spaceID: originSpaceID)
        }
    }

    /// The DesktopKey for a display on the current space, respecting mode.
    private func desktopKey(for displayID: CGDirectDisplayID) -> DesktopKey {
        switch mode {
        case .allDesktops:
            return DesktopKey(displayID: displayID)
        case .perDesktop:
            return DesktopKey(displayID: displayID, spaceID: currentSpaceID(for: displayID))
        }
    }

    /// Remove wallpaper from a specific display (current space in perDesktop mode).
    func clearWallpaper(for displayID: CGDirectDisplayID) {
        cancelAssignment(for: .display(displayID))
        cancelRestoreTask()
        let key = desktopKey(for: displayID)
        desktopFiles.removeValue(forKey: key)
        youtubeURLs.removeValue(forKey: key)
        playbackPositions.removeValue(forKey: key)
        if let controller = controllers.removeValue(forKey: displayID) {
            controller.close()
        }
        saveState()
    }

    /// Remove all wallpapers.
    func clearAllWallpapers() {
        cancelAllAssignments()
        cancelRestoreTask()
        desktopFiles.removeAll()
        youtubeURLs.removeAll()
        playbackPositions.removeAll()
        tearDownWindows()
        saveState()
    }

    /// Switch modes.
    func setMode(_ newMode: WallpaperMode) {
        guard newMode != mode else { return }
        cancelAllAssignments()
        cancelRestoreTask()

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
                let newKey = DesktopKey(
                    displayID: key.displayID,
                    spaceID: currentSpaceID(for: key.displayID)
                )
                desktopFiles[newKey] = url
                if let yt = oldYT[key] { youtubeURLs[newKey] = yt }
                knownSpaces[key.displayID, default: []].insert(newKey.spaceID)
            }
        }

        mode = newMode
        saveState()
        rebuildAllWindows()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            cancelAllAssignments()
            cancelRestoreTask()
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
        persistenceStore.save(
            mode: mode,
            isMuted: isMuted,
            desktopFiles: desktopFiles,
            youtubeURLs: youtubeURLs
        )
    }

    private func restoreState() {
        let state = persistenceStore.load()
        mode = state.mode
        isMuted = state.isMuted
        desktopFiles = state.desktopFiles
        youtubeURLs = state.youtubeURLs

        for (displayID, spaces) in state.knownSpaces {
            knownSpaces[displayID, default: []].formUnion(spaces)
        }

        scheduleRestoreRedownloads(state.needsRedownload)

        if !desktopFiles.isEmpty {
            rebuildAllWindows()
        }
    }

    private func scheduleRestoreRedownloads(_ items: [WallpaperRedownloadRequest]) {
        guard !items.isEmpty else { return }
        cancelRestoreTask()

        restoreTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for item in items {
                let key = item.key
                let youtubeURL = item.youtubeURL

                guard !Task.isCancelled else { return }
                guard desktopFiles[key] == nil, youtubeURLs[key] == youtubeURL else { continue }

                activeDownloadSource = .restore
                guard let localURL = await youtubeDownloader.download(youtubeURL: youtubeURL) else {
                    if activeDownloadSource == .restore {
                        activeDownloadSource = nil
                    }
                    guard !Task.isCancelled else { return }
                    continue
                }
                if activeDownloadSource == .restore {
                    activeDownloadSource = nil
                }

                guard !Task.isCancelled else { return }
                guard desktopFiles[key] == nil, youtubeURLs[key] == youtubeURL else { continue }

                desktopFiles[key] = localURL
                knownSpaces[key.displayID, default: []].insert(key.spaceID)
                saveState()
                rebuildAllWindows()
            }

            if activeDownloadSource == .restore {
                activeDownloadSource = nil
            }
            restoreTask = nil
        }
    }

    // MARK: - Window Lifecycle

    func rebuildAllWindows() {
        guard !isPaused, !systemPaused else {
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
        cancelAllAssignments()
        cancelRestoreTask()
        tearDownWindows()
        removeScreenObserver()
        removeSpaceObserver()
        downloadOverlayObserver = nil
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
                self.refreshManagedDisplaySpaces()

                if self.mode == .allDesktops {
                    let displayIDs = NSScreen.screens.compactMap(\.displayID)
                    let reconciledFiles = AllDesktopAssignmentReconciler.reconcile(
                        existing: self.desktopFiles,
                        connectedDisplayIDs: displayIDs,
                        sharedValue: self.sharedFileURL
                    )
                    let reconciledYouTubeURLs = AllDesktopAssignmentReconciler.reconcile(
                        existing: self.youtubeURLs,
                        connectedDisplayIDs: displayIDs,
                        sharedValue: self.youtubeURLs.values.first
                    )

                    if reconciledFiles.didChange {
                        self.desktopFiles = reconciledFiles.assignments
                    }
                    if reconciledYouTubeURLs.didChange {
                        self.youtubeURLs = reconciledYouTubeURLs.assignments
                    }
                    if reconciledFiles.didChange || reconciledYouTubeURLs.didChange {
                        self.saveState()
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
                self.refreshManagedDisplaySpaces()
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
