import AppKit
import AVFoundation
import Combine

/// Central coordinator: manages per-screen wallpaper windows, file selection,
/// playback state, sound, space tracking, and power-aware pause/resume.
@MainActor
final class WallpaperManager: ObservableObject {

    // MARK: - Published State

    /// All per-desktop wallpaper assignments, playback positions, and observed Spaces.
    @Published var state: WallpaperState = .init()

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

    private let router = WallpaperWindowRouter()
    private var screenObserver: Any?
    private var spaceObserver: Any?
    private var powerMonitor: PowerStateMonitor?
    private var systemPaused: Bool = false
    private let loadingOverlay = LoadingOverlayController()
    private var downloadOverlayObserver: AnyCancellable?
    private let requestCoordinator = WallpaperRequestCoordinator()
    private let persistenceStore = WallpaperPersistenceStore()
    private var restoreTask: Task<Void, Never>?
    @Published private(set) var activeSpaceIDs: [CGDirectDisplayID: UInt64] = [:]

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
            state.knownSpaces[displayID, default: []].formUnion(spaces)
        }
    }

    private func currentSpaceID(for displayID: CGDirectDisplayID) -> UInt64 {
        activeSpaceIDs[displayID] ?? currentGlobalSpaceID()
    }

    // MARK: - Computed Helpers

    /// In allDesktops mode, returns the single shared file URL (if any).
    var sharedFileURL: URL? {
        guard mode == .allDesktops else { return nil }
        return state.sharedLocalURL
    }

    /// File URL for a display, respecting the current mode and space.
    func fileURL(for displayID: CGDirectDisplayID) -> URL? {
        state.localURL(for: desktopKey(for: displayID))
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
        let spaces = state.knownSpaces[displayID] ?? []
        let currentSpace = currentSpaceID(for: displayID)
        return spaces.sorted().map { spaceID in
            let key = DesktopKey(displayID: displayID, spaceID: spaceID)
            let fileName = state.localURL(for: key)?.lastPathComponent ?? "No MovingPaper"
            return (spaceID: spaceID, fileName: fileName, isCurrent: spaceID == currentSpace)
        }
    }

    /// Whether any desktop has a wallpaper assigned.
    var hasAnyWallpaper: Bool { !state.isEmpty }

    // MARK: - File Selection

    private func assignmentTarget(for displayID: CGDirectDisplayID?) -> WallpaperAssignmentTarget {
        if let displayID {
            return .display(displayID)
        }
        return .allDesktops
    }

    /// Cancelling the restore Task propagates through `withTaskCancellationHandler`
    /// in `YouTubeDownloader.runYTDLP`, which terminates the subprocess. No
    /// separate downloader-cancel bookkeeping needed.
    private func cancelRestoreTask() {
        restoreTask?.cancel()
        restoreTask = nil
    }

    private func cancelAssignment(for target: WallpaperAssignmentTarget) {
        requestCoordinator.cancel(target)
        loadingOverlay.hide()
        AppPresentation.returnToAccessory()
    }

    private func cancelAllAssignments() {
        requestCoordinator.cancelAll()
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

    private func applyWallpaper(
        url: URL,
        for displayID: CGDirectDisplayID? = nil,
        spaceID: UInt64? = nil,
        youtubeOrigin: String? = nil
    ) {
        isPaused = false

        switch mode {
        case .allDesktops:
            let entry = WallpaperEntry(localURL: url, youtubeOrigin: youtubeOrigin)
            state.applyShared(entry: entry, across: NSScreen.screens.compactMap(\.displayID))
        case .perDesktop:
            if let id = displayID {
                let space = spaceID ?? currentSpaceID(for: id)
                let key = DesktopKey(displayID: id, spaceID: space)
                state.setEntry(WallpaperEntry(localURL: url, youtubeOrigin: youtubeOrigin), for: key)
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
            guard let localURL = await youtubeDownloader.download(youtubeURL: urlString) else {
                guard requestCoordinator.isCurrent(token, for: target) else { return }
                if case .failed(let msg) = youtubeDownloader.state {
                    showAlert(title: "Download Failed", message: msg)
                }
                return
            }
            guard requestCoordinator.isCurrent(token, for: target) else { return }

            applyWallpaper(
                url: localURL,
                for: displayID,
                spaceID: originSpaceID,
                youtubeOrigin: urlString
            )
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
        state.clearEntry(for: desktopKey(for: displayID))
        router.closeController(for: displayID)
        saveState()
    }

    /// Remove all wallpapers.
    func clearAllWallpapers() {
        cancelAllAssignments()
        cancelRestoreTask()
        state.entries.removeAll()
        state.playbackPositions.removeAll()
        tearDownWindows()
        saveState()
    }

    /// Switch modes.
    func setMode(_ newMode: WallpaperMode) {
        guard newMode != mode else { return }
        cancelAllAssignments()
        cancelRestoreTask()

        switch newMode {
        case .allDesktops:
            if let shared = state.entries.values.first {
                state.applyShared(entry: shared, across: NSScreen.screens.compactMap(\.displayID))
            }
        case .perDesktop:
            state.migrateToPerDesktop { [activeSpaceIDs] displayID in
                activeSpaceIDs[displayID] ?? currentGlobalSpaceID()
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
        router.setMuted(isMuted)
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
        persistenceStore.save(mode: mode, isMuted: isMuted, state: state)
    }

    private func restoreState() {
        let persisted = persistenceStore.load()
        mode = persisted.mode
        isMuted = persisted.isMuted
        state = persisted.state

        scheduleRestoreRedownloads(persisted.needsRedownload)

        if !state.isEmpty {
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
                guard state.entries[key] == nil else { continue }

                guard let localURL = await youtubeDownloader.download(youtubeURL: youtubeURL) else {
                    guard !Task.isCancelled else { return }
                    continue
                }

                guard !Task.isCancelled else { return }
                guard state.entries[key] == nil else { continue }

                state.setEntry(
                    WallpaperEntry(localURL: localURL, youtubeOrigin: youtubeURL),
                    for: key
                )
                saveState()
                rebuildAllWindows()
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

        router.setMuted(isMuted)
        router.reconcile(screens: NSScreen.screens) { [self] displayID in
            guard let url = fileURL(for: displayID),
                  let type = fileType(for: url) else { return nil }
            let key = desktopKey(for: displayID)
            return WallpaperWindowRouter.Plan(
                url: url,
                type: type,
                resumeTime: state.playbackPositions[key]
            )
        }
    }

    func tearDown() {
        cancelAllAssignments()
        cancelRestoreTask()
        tearDownWindows()
        removeScreenObserver()
        removeSpaceObserver()
        downloadOverlayObserver = nil
        powerMonitor?.stop()
        powerMonitor = nil
    }

    private func tearDownWindows() {
        savePlaybackPositions()
        router.closeAll()
    }

    private func savePlaybackPositions() {
        for (displayID, time) in router.currentPlaybackTimes() {
            state.playbackPositions[desktopKey(for: displayID)] = time
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
                    if self.state.reconcileAllDesktops(connectedDisplayIDs: displayIDs) {
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
        let monitor = PowerStateMonitor { [weak self] shouldPause in
            self?.applyPowerVerdict(shouldPause: shouldPause)
        }
        powerMonitor = monitor
        monitor.start()
    }

    private func applyPowerVerdict(shouldPause: Bool) {
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
