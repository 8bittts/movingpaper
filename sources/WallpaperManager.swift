import AppKit

/// Central coordinator: manages per-screen wallpaper windows, file selection,
/// playback state, sound, space tracking, and power-aware pause/resume.
@MainActor
final class WallpaperManager {

    // MARK: - State

    /// All per-desktop wallpaper assignments, playback positions, and observed Spaces.
    private var state = WallpaperState()
    /// Whether all desktops share one wallpaper or each gets its own.
    private var mode = WallpaperMode.allDesktops
    /// User-initiated pause (distinct from system pause).
    private var isPaused = false
    private var isMuted = true
    /// Pause imposed by Low Power Mode or thermal pressure.
    private var systemPaused = false
    private var activeSpaceIDs: [CGDirectDisplayID: UInt64] = [:]
    /// YouTube redownloads still outstanding this session, keyed by desktop.
    /// Re-persisted on every save so an unrelated save can't erase them before
    /// the download finishes; dropped when resolved or the desktop is cleared.
    private var pendingRedownloads: [DesktopKey: WallpaperRedownloadRequest] = [:]
    /// Files already reported as unplayable, so each one alerts once until it
    /// is assigned again.
    private var reportedPlaybackFailures: Set<String> = []

    // MARK: - Collaborators

    private let router = WallpaperWindowRouter()
    private let youtubeDownloader = YouTubeDownloader()
    private let loadingOverlay = LoadingOverlayController()
    private let requestCoordinator = WallpaperRequestCoordinator()
    private let persistenceStore = WallpaperPersistenceStore()
    private var powerMonitor: PowerStateMonitor?
    private var screenObserver: Any?
    private var spaceObserver: Any?
    private var restoreTask: Task<Void, Never>?

    init() {
        router.onPlaybackFailure = { [weak self] url, message in
            self?.handlePlaybackFailure(url: url, message: message)
        }
        refreshManagedDisplaySpaces()
        restoreState()
        observeScreenChanges()
        observeSpaceChanges()
        observePowerState()
    }

    func tearDown() {
        cancelAllRequests()
        tearDownWindows()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        screenObserver = nil
        spaceObserver = nil
        powerMonitor?.stop()
        powerMonitor = nil
    }

    // MARK: - Displays and Spaces

    private var connectedDisplayIDs: [CGDirectDisplayID] {
        NSScreen.screens.compactMap(\.displayID)
    }

    /// Resolve the `NSScreen` for a target display, or nil (→ main screen) for the
    /// all-desktops / no-target case.
    private func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { $0.displayID == displayID }
    }

    private func refreshManagedDisplaySpaces() {
        let snapshot = ManagedDisplaySpacesSnapshot.current()
        activeSpaceIDs = snapshot.activeSpaceByDisplayID

        for (displayID, spaces) in snapshot.knownSpacesByDisplayID {
            state.knownSpaces[displayID, default: []].formUnion(spaces)
        }
    }

    private func currentSpaceID(for displayID: CGDirectDisplayID) -> UInt64 {
        activeSpaceIDs[displayID] ?? ManagedDisplaySpacesSnapshot.activeGlobalSpaceID()
    }

    /// The DesktopKey for a display on the current space, respecting mode.
    private func desktopKey(for displayID: CGDirectDisplayID) -> DesktopKey {
        switch mode {
        case .allDesktops:
            DesktopKey(displayID: displayID)
        case .perDesktop:
            DesktopKey(displayID: displayID, spaceID: currentSpaceID(for: displayID))
        }
    }

    // MARK: - Menu

    /// Snapshot the status menu needs without exposing the downloader.
    func menuInput(canCheckForUpdates: Bool, openAtLogin: Bool) -> MenuModelInput {
        MenuModelInput(
            downloadProgress: youtubeDownloader.progress,
            mode: mode,
            isMuted: isMuted,
            isPaused: isPaused,
            hasAnyWallpaper: !state.isEmpty,
            sharedFileName: mode == .allDesktops ? state.sharedLocalURL?.lastPathComponent : nil,
            canCheckForUpdates: canCheckForUpdates,
            openAtLogin: openAtLogin,
            displays: NSScreen.screens.compactMap { screen in
                screen.displayID.map { displayID in
                    DisplayMenuInput(
                        id: displayID,
                        name: screen.localizedName,
                        spaces: spaceMenuInputs(for: displayID)
                    )
                }
            }
        )
    }

    /// Every known Space of a display, sorted by space ID, with and without
    /// wallpapers — we track every Space the user visits.
    private func spaceMenuInputs(for displayID: CGDirectDisplayID) -> [SpaceMenuInput] {
        let currentSpace = currentSpaceID(for: displayID)
        return (state.knownSpaces[displayID] ?? []).sorted().map { spaceID in
            let key = DesktopKey(displayID: displayID, spaceID: spaceID)
            return SpaceMenuInput(
                fileName: state.localURL(for: key)?.lastPathComponent,
                isCurrent: spaceID == currentSpace
            )
        }
    }

    /// Local file paths currently referenced by live wallpaper assignments.
    /// Used to protect in-use cache files from eviction by `CacheJanitor`.
    var referencedLocalPaths: Set<String> {
        Set(state.entries.values.map { $0.localURL.path(percentEncoded: false) })
    }

    // MARK: - Request Cancellation

    private func assignmentTarget(for displayID: CGDirectDisplayID?) -> WallpaperAssignmentTarget {
        displayID.map { .display($0) } ?? .allDesktops
    }

    /// Cancelling the restore Task propagates through `withTaskCancellationHandler`
    /// in `YouTubeDownloader.runYTDLP`, which terminates the subprocess. No
    /// separate downloader-cancel bookkeeping needed.
    private func cancelRestoreTask() {
        restoreTask?.cancel()
        restoreTask = nil
    }

    /// Cancel the in-flight request for one target and dismiss the UI it raised.
    private func cancelAssignment(for target: WallpaperAssignmentTarget) {
        requestCoordinator.cancel(target)
        loadingOverlay.hide()
        AppPresentation.returnToAccessory()
    }

    /// Cancel every in-flight request, including the restore-redownload batch.
    private func cancelAllRequests() {
        requestCoordinator.cancelAll()
        cancelRestoreTask()
        loadingOverlay.hide()
        AppPresentation.returnToAccessory()
    }

    func cancelDownload() {
        youtubeDownloader.cancel()
    }

    // MARK: - Sources

    /// Open file picker and assign result.
    func selectFile(for displayID: CGDirectDisplayID? = nil) {
        AppPresentation.withForegroundActivation {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.gif, .mpeg4Movie, .quickTimeMovie, .movie]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.message = "Choose a GIF or video file to use as your wallpaper."

            guard panel.runModal() == .OK, let url = panel.url else { return }
            setWallpaper(url: url, for: displayID)
        }
    }

    /// Assign a wallpaper file: cancel the in-flight assignment for the target,
    /// then apply the wallpaper synchronously on the current space.
    ///
    /// This path uses only a local file (never the shared `YouTubeDownloader`), so
    /// it deliberately does NOT cancel the restore-redownload batch — that batch
    /// self-skips any key already assigned (`isAwaitingRedownload`).
    func setWallpaper(url: URL, for displayID: CGDirectDisplayID? = nil) {
        cancelAssignment(for: assignmentTarget(for: displayID))
        applyWallpaper(url: url, for: displayID)
    }

    /// Download a YouTube video and set it as wallpaper.
    func setYouTubeWallpaper(urlString: String, for displayID: CGDirectDisplayID? = nil) {
        guard YouTubeURLParser.isYouTubeURL(urlString) else {
            AppPresentation.showAlert(
                title: "Invalid URL",
                message: "That doesn't look like a YouTube URL."
            )
            return
        }

        let target = assignmentTarget(for: displayID)
        let originSpaceID = displayID.map { currentSpaceID(for: $0) }
        cancelRestoreTask()
        requestCoordinator.start(for: target) { [weak self] token in
            guard let self else { return }
            let outcome = await youtubeDownloader.download(youtubeURL: urlString) { [weak self] progress in
                self?.showDownloadProgress(progress, on: displayID)
            }
            guard requestCoordinator.isCurrent(token, for: target) else { return }

            switch outcome {
            case .success(let localURL):
                applyWallpaper(
                    url: localURL,
                    for: displayID,
                    spaceID: originSpaceID,
                    youtubeOrigin: urlString
                )
            case .failure(let message):
                AppPresentation.showAlert(title: "Download Failed", message: message, style: .warning)
            case .cancelled:
                break
            }
        }
    }

    /// Pick a random video from the entire Photos library and set it as wallpaper.
    func shuffleFromPhotos(for displayID: CGDirectDisplayID? = nil) {
        AppPresentation.promoteToForeground()
        let target = assignmentTarget(for: displayID)
        let originSpaceID = displayID.map { currentSpaceID(for: $0) }
        requestCoordinator.start(for: target) { [weak self] token in
            guard let self else { return }
            loadingOverlay.show(message: "Shuffling…", on: screen(for: displayID))
            let outcome = await PhotosService.shuffle()
            guard requestCoordinator.isCurrent(token, for: target) else { return }
            loadingOverlay.hide()
            AppPresentation.returnToAccessory()

            switch outcome {
            case .video(let url):
                applyWallpaper(url: url, for: displayID, spaceID: originSpaceID)
            case .failed(let failure):
                AppPresentation.showAlert(title: failure.alertTitle, message: failure.alertMessage)
            }
        }
    }

    private func applyWallpaper(
        url: URL,
        for displayID: CGDirectDisplayID?,
        spaceID: UInt64? = nil,
        youtubeOrigin: String? = nil
    ) {
        guard WallpaperFileType.detect(for: url) != nil else {
            AppPresentation.showAlert(
                title: "Unsupported File",
                message: "Choose a GIF or video file (.gif, .mp4, .mov, or .m4v)."
            )
            return
        }

        isPaused = false
        reportedPlaybackFailures.remove(url.path(percentEncoded: false))
        let keys = state.assign(
            WallpaperEntry(localURL: url, youtubeOrigin: youtubeOrigin),
            mode: mode,
            displayID: displayID,
            spaceID: spaceID,
            connectedDisplayIDs: connectedDisplayIDs,
            currentSpaceID: { [self] displayID in currentSpaceID(for: displayID) }
        )
        for key in keys {
            pendingRedownloads[key] = nil
        }

        saveState()
        rebuildAllWindows()
    }

    /// Drives the overlay for one YouTube download: a fraction while it runs,
    /// nil once it ends. Centered on the display the download is for.
    private func showDownloadProgress(_ progress: Double?, on displayID: CGDirectDisplayID?) {
        guard let progress else {
            loadingOverlay.hide()
            return
        }
        loadingOverlay.show(
            message: MenuBarLabelFormatter.downloadStatus(progress: progress),
            progress: progress,
            on: screen(for: displayID)
        )
    }

    private func handlePlaybackFailure(url: URL, message: String) {
        let path = url.path(percentEncoded: false)
        Log.playback.error("Playback failed for \(path, privacy: .public): \(message, privacy: .public)")
        guard reportedPlaybackFailures.insert(path).inserted else { return }
        AppPresentation.showAlert(title: "Playback Failed", message: message, style: .warning)
    }

    // MARK: - Removal, Mode, Playback

    /// Remove wallpaper from a specific display (current space in perDesktop mode).
    func clearWallpaper(for displayID: CGDirectDisplayID) {
        cancelAssignment(for: .display(displayID))
        let key = desktopKey(for: displayID)
        pendingRedownloads[key] = nil
        state.clearEntry(for: key)
        router.closeController(for: displayID)
        saveState()
    }

    /// Remove all wallpapers.
    func clearAllWallpapers() {
        cancelAllRequests()
        pendingRedownloads.removeAll()
        state.entries.removeAll()
        state.playbackPositions.removeAll()
        tearDownWindows()
        saveState()
    }

    /// Switch modes.
    func setMode(_ newMode: WallpaperMode) {
        guard newMode != mode else { return }
        cancelAllRequests()

        switch newMode {
        case .allDesktops:
            if let shared = state.canonicalEntry {
                state.applyShared(entry: shared, across: connectedDisplayIDs)
            }
        case .perDesktop:
            state.migrateToPerDesktop { [self] displayID in currentSpaceID(for: displayID) }
        }

        mode = newMode
        saveState()
        rebuildAllWindows()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            cancelAllRequests()
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

    /// Whether a restore redownload is still wanted: not resolved, not cleared,
    /// and not replaced by a wallpaper the user has assigned since.
    private func isAwaitingRedownload(_ key: DesktopKey) -> Bool {
        pendingRedownloads[key] != nil && state.entries[key] == nil
    }

    private func scheduleRestoreRedownloads(_ items: [WallpaperRedownloadRequest]) {
        guard !items.isEmpty else { return }
        cancelRestoreTask()

        restoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var failedCount = 0

            for item in items {
                guard !Task.isCancelled else { return }
                guard isAwaitingRedownload(item.key) else { continue }

                let outcome = await youtubeDownloader.download(youtubeURL: item.youtubeURL) { [weak self] progress in
                    self?.showDownloadProgress(progress, on: nil)
                }
                guard !Task.isCancelled else { return }

                switch outcome {
                case .success(let localURL):
                    guard isAwaitingRedownload(item.key) else { continue }
                    state.setEntry(
                        WallpaperEntry(localURL: localURL, youtubeOrigin: item.youtubeURL),
                        for: item.key
                    )
                    pendingRedownloads[item.key] = nil
                    saveState()
                    rebuildAllWindows()
                case .failure:
                    failedCount += 1
                case .cancelled:
                    // Cancelled from the menu: not a failure. The request stays
                    // persisted, so the next launch retries it.
                    break
                }
            }

            if failedCount > 0 {
                let message = failedCount == 1
                    ? "A YouTube wallpaper couldn't be downloaded again."
                    : "\(failedCount) YouTube wallpapers couldn't be downloaded again."
                AppPresentation.showAlert(
                    title: "Couldn't Restore Some Wallpapers",
                    message: message,
                    style: .warning
                )
            }

            restoreTask = nil
        }
    }

    // MARK: - Window Lifecycle

    private func rebuildAllWindows() {
        guard !isPaused else {
            tearDownWindows()
            return
        }

        router.setMuted(isMuted)
        router.reconcile(screens: NSScreen.screens) { [self] displayID in
            let key = desktopKey(for: displayID)
            guard let url = state.localURL(for: key),
                  let type = WallpaperFileType.detect(for: url) else { return nil }
            return WallpaperWindowRouter.Plan(
                url: url,
                type: type,
                resumeTime: state.playbackPositions[key]
            )
        }
        router.setPlaybackSuspended(systemPaused)
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

    // MARK: - System Observers

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenChange()
            }
        }
    }

    private func handleScreenChange() {
        refreshManagedDisplaySpaces()
        if mode == .allDesktops, state.reconcileAllDesktops(connectedDisplayIDs: connectedDisplayIDs) {
            saveState()
        }
        rebuildAllWindows()
    }

    private func observeSpaceChanges() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSpaceChange()
            }
        }
    }

    private func handleSpaceChange() {
        // Positions belong to the Space being left, so save them before the
        // active-Space table moves on.
        savePlaybackPositions()
        refreshManagedDisplaySpaces()
        // In allDesktops mode the panels have .canJoinAllSpaces — no rebuild needed.
        if mode == .perDesktop {
            rebuildAllWindows()
        }
    }

    private func observePowerState() {
        let monitor = PowerStateMonitor { [weak self] shouldPause in
            self?.applyPowerVerdict(shouldPause: shouldPause)
        }
        powerMonitor = monitor
        monitor.start()
    }

    private func applyPowerVerdict(shouldPause: Bool) {
        guard shouldPause != systemPaused else { return }
        systemPaused = shouldPause
        guard !isPaused else { return }
        if shouldPause {
            router.setPlaybackSuspended(true)
        } else {
            rebuildAllWindows()
        }
    }
}
