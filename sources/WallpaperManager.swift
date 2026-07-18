import AppKit
import AVFoundation
import Combine

/// Central coordinator: manages per-screen wallpaper windows, file selection,
/// playback state, sound, space tracking, and power-aware pause/resume.
@MainActor
final class WallpaperManager {

    // MARK: - State

    /// All per-desktop wallpaper assignments, playback positions, and observed Spaces.
    var state: WallpaperState = .init()

    /// Whether all desktops share one wallpaper or each gets its own.
    var mode: WallpaperMode = .allDesktops

    /// User-initiated pause (distinct from system pause).
    var isPaused: Bool = false

    /// Whether video audio is muted.
    var isMuted: Bool = true

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
    /// Display whose YouTube download is currently in flight, so the progress
    /// overlay (driven by a global `$state` observer with no per-call display
    /// context) can center on the right screen.
    private var activeDownloadDisplayID: CGDirectDisplayID?
    private var downloadOverlayObserver: AnyCancellable?
    private let requestCoordinator = WallpaperRequestCoordinator()
    private let persistenceStore = WallpaperPersistenceStore()
    private var restoreTask: Task<Void, Never>?
    /// YouTube redownloads still outstanding this session, keyed by desktop.
    /// Re-persisted on every save so an unrelated save can't erase them before
    /// the download finishes; dropped when resolved or the desktop is cleared.
    private var pendingRedownloads: [DesktopKey: WallpaperRedownloadRequest] = [:]
    private(set) var activeSpaceIDs: [CGDirectDisplayID: UInt64] = [:]

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

    /// Display IDs of all connected screens.
    private var connectedDisplayIDs: [CGDirectDisplayID] {
        NSScreen.screens.compactMap(\.displayID)
    }

    /// All known Spaces for a display, sorted by space ID.
    /// Includes Spaces with and without wallpapers — we track every Space the user visits.
    func spaceAssignments(for displayID: CGDirectDisplayID) -> [(spaceID: UInt64, fileName: String?, isCurrent: Bool)] {
        let spaces = state.knownSpaces[displayID] ?? []
        let currentSpace = currentSpaceID(for: displayID)
        return spaces.sorted().map { spaceID in
            let key = DesktopKey(displayID: displayID, spaceID: spaceID)
            // nil means no wallpaper on this Space — the UI supplies the label.
            let fileName = state.localURL(for: key)?.lastPathComponent
            return (spaceID: spaceID, fileName: fileName, isCurrent: spaceID == currentSpace)
        }
    }

    /// Whether any desktop has a wallpaper assigned.
    var hasAnyWallpaper: Bool { !state.isEmpty }

    /// Local file paths currently referenced by live wallpaper assignments.
    /// Used to protect in-use cache files from eviction by `CacheJanitor`.
    var referencedLocalPaths: Set<String> {
        Set(state.entries.values.map { $0.localURL.path(percentEncoded: false) })
    }

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

    /// Assign a wallpaper file: cancel the in-flight assignment for the target,
    /// then apply the wallpaper synchronously on the current space.
    ///
    /// This path uses only a local file (never the shared `YouTubeDownloader`), so
    /// it deliberately does NOT cancel the restore-redownload batch — that batch
    /// self-skips any key already assigned (`state.entries[key] == nil` guard).
    func setWallpaper(url: URL, for displayID: CGDirectDisplayID? = nil) {
        cancelAssignment(for: assignmentTarget(for: displayID))
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
            state.applyShared(entry: entry, across: connectedDisplayIDs)
        case .perDesktop:
            let entry = WallpaperEntry(localURL: url, youtubeOrigin: youtubeOrigin)
            if let id = displayID {
                let space = spaceID ?? currentSpaceID(for: id)
                state.setEntry(entry, for: DesktopKey(displayID: id, spaceID: space))
            } else {
                // A "for all" pick that resolves while in perDesktop mode (e.g. the
                // picker opened in allDesktops, then the user switched modes): apply
                // to every connected display on its current space rather than
                // silently dropping the chosen media.
                for displayID in connectedDisplayIDs {
                    let key = DesktopKey(displayID: displayID, spaceID: currentSpaceID(for: displayID))
                    state.setEntry(entry, for: key)
                }
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
        activeDownloadDisplayID = displayID
        cancelRestoreTask()
        requestCoordinator.start(for: target) { [weak self] token in
            guard let self else { return }
            let outcome = await youtubeDownloader.download(youtubeURL: urlString)
            guard requestCoordinator.isCurrent(token, for: target) else { return }

            switch outcome {
            case .success(let localURL):
                applyWallpaper(
                    url: localURL,
                    for: displayID,
                    spaceID: originSpaceID,
                    youtubeOrigin: urlString
                )
            case .failure(let msg):
                showAlert(title: "Download Failed", message: msg)
            case .cancelled:
                break
            }
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
        requestCoordinator.start(for: target) { [weak self] token in
            guard let self else { return }
            loadingOverlay.show(message: "Shuffling…", on: screen(for: displayID))
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
        pendingRedownloads[desktopKey(for: displayID)] = nil
        state.clearEntry(for: desktopKey(for: displayID))
        router.closeController(for: displayID)
        saveState()
    }

    /// Remove all wallpapers.
    func clearAllWallpapers() {
        cancelAllAssignments()
        cancelRestoreTask()
        pendingRedownloads.removeAll()
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
            if let shared = state.canonicalEntry {
                state.applyShared(entry: shared, across: connectedDisplayIDs)
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

    /// Resolve the `NSScreen` for a target display, or nil (→ main screen) for the
    /// all-desktops / no-target case.
    private func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { $0.displayID == displayID }
    }

    private func observeDownloadState() {
        downloadOverlayObserver = youtubeDownloader.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .downloading(let progress):
                    let pct = Int(progress * 100)
                    self.loadingOverlay.show(
                        message: "Downloading \(pct)%",
                        progress: progress,
                        on: self.screen(for: self.activeDownloadDisplayID)
                    )
                case .idle, .failed:
                    self.loadingOverlay.hide()
                    self.activeDownloadDisplayID = nil
                }
            }
    }

    // MARK: - Persistence

    private func saveState() {
        persistenceStore.save(
            mode: mode,
            isMuted: isMuted,
            state: state,
            pendingRedownloads: Array(pendingRedownloads.values)
        )
    }

    private func restoreState() {
        let persisted = persistenceStore.load()
        mode = persisted.mode
        isMuted = persisted.isMuted
        state.adopt(persisted: persisted.state)

        for request in persisted.needsRedownload {
            pendingRedownloads[request.key] = request
        }
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

                guard case .success(let localURL) = await youtubeDownloader.download(youtubeURL: youtubeURL) else {
                    guard !Task.isCancelled else { return }
                    continue
                }

                guard !Task.isCancelled else { return }
                guard state.entries[key] == nil else { continue }

                state.setEntry(
                    WallpaperEntry(localURL: localURL, youtubeOrigin: youtubeURL),
                    for: key
                )
                pendingRedownloads[key] = nil
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
                    if self.state.reconcileAllDesktops(connectedDisplayIDs: self.connectedDisplayIDs) {
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
