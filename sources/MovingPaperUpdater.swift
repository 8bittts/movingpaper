import AppKit
@preconcurrency import Sparkle

/// Sparkle auto-updater wrapper for MovingPaper.
/// Uses Sparkle's standard UI (native macOS alerts) with activation policy
/// management for menu-bar-only apps.
@MainActor
final class MovingPaperUpdater: NSObject {

    /// Nil when the host bundle carries no Sparkle configuration (`swift run`).
    private var updaterController: SPUStandardUpdaterController?
    private var windowObserver: Any?
    /// Whether this session holds `AppPresentation.Reason.updater`. Sparkle has
    /// three entry points into one session and a single finish, so the hold is
    /// taken once per session rather than once per entry point.
    private var holdsPresentation = false

    /// Whether Sparkle can start a check right now. The status menu reads it
    /// each time it opens.
    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    override init() {
        super.init()

        guard Self.hostHasSparkleConfig() else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    /// Start the updater (call once after app launch).
    func start() {
        do {
            try updaterController?.updater.start()
        } catch {
            Log.updater.error("Updater failed to start: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Trigger a manual update check (user-initiated).
    func checkForUpdates() {
        guard let controller = updaterController else {
            Log.updater.error("Updates unavailable in development builds.")
            return
        }

        beginPresentation()
        controller.updater.checkForUpdates()
    }

    // MARK: - Presentation

    /// Foreground the accessory app and float Sparkle's windows for this session.
    private func beginPresentation() {
        if holdsPresentation {
            NSApp.activate()
        } else {
            holdsPresentation = true
            AppPresentation.begin(.updater)
        }
        startFloatingWindows()
    }

    private func endPresentation() {
        stopFloatingWindows()
        guard holdsPresentation else { return }
        holdsPresentation = false
        AppPresentation.end(.updater)
    }

    /// Float Sparkle's own windows above other apps' windows so they aren't
    /// buried. Only windows whose controller comes from the Sparkle framework are
    /// raised; an open panel or alert of ours keeps its standard level.
    private func startFloatingWindows() {
        guard windowObserver == nil else { return }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                if Self.isSparkleWindow(window) {
                    window.level = .floating
                }
            }
        }
    }

    private static let sparkleBundle = Bundle(for: SPUStandardUpdaterController.self)

    private static func isSparkleWindow(_ window: NSWindow) -> Bool {
        guard let controller = window.windowController else { return false }
        return Bundle(for: type(of: controller)) == sparkleBundle
    }

    private func stopFloatingWindows() {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
    }

    // MARK: - Host Validation

    private static func hostHasSparkleConfig() -> Bool {
        ["CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString", "SUFeedURL", "SUPublicEDKey"]
            .allSatisfy { key in
                (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.isEmpty == false
            }
    }
}

// MARK: - SPUUpdaterDelegate

@MainActor
extension MovingPaperUpdater: SPUUpdaterDelegate {

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString.isEmpty ? item.versionString : item.displayVersionString
        Log.updater.info("Update available: \(version, privacy: .public)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Log.updater.info("No update found")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let error = error as NSError
        // Sparkle ends a check that found nothing through this path too.
        if error.domain == SUSparkleErrorDomain, error.code == Int(SUError.noUpdateError.rawValue) { return }
        let message = error.localizedDescription
        Log.updater.error("Sparkle aborted: \(message, privacy: .public)")
    }
}

// MARK: - SPUStandardUserDriverDelegate

@MainActor
extension MovingPaperUpdater: @preconcurrency SPUStandardUserDriverDelegate {

    /// Modal alerts ("You're up to date", update errors, permission prompts) only
    /// fire this hook — not `willHandleShowingUpdate` — so a menu-bar (accessory)
    /// app must foreground itself here too, or the alert surfaces without focus or
    /// behind other windows. Mirrors the update-available path below.
    func standardUserDriverWillShowModalAlert() {
        beginPresentation()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        beginPresentation()
    }

    func standardUserDriverWillFinishUpdateSession() {
        endPresentation()
    }
}
