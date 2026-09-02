import AppKit
import Combine
@preconcurrency import Sparkle

/// Sparkle auto-updater wrapper for MovingPaper.
/// Uses Sparkle's standard UI (native macOS alerts) with activation policy
/// management for menu-bar-only apps.
@MainActor
final class MovingPaperUpdater: NSObject, ObservableObject {

    @Published private(set) var canCheckForUpdates = false

    private var updaterController: SPUStandardUpdaterController?
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var windowObserver: Any?

    override init() {
        super.init()

        guard Self.hostHasSparkleConfig() else { return }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        self.updaterController = controller

        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    /// Start the updater (call once after app launch).
    func start() {
        guard !started else { return }
        started = true
        guard let controller = updaterController else { return }

        do {
            try controller.updater.start()
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

        AppPresentation.promoteToForeground()
        startFloatingWindows()
        controller.updater.checkForUpdates()
    }

    // MARK: - Window Level

    /// Float Sparkle's dialogs above all windows so they aren't buried.
    private func startFloatingWindows() {
        guard windowObserver == nil else { return }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                window.level = .floating
            }
        }
    }

    private func stopFloatingWindows() {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
    }

    // MARK: - Host Validation

    nonisolated private static func hostHasSparkleConfig() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier,
              !bundleID.isEmpty else { return false }
        guard let buildVersion = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String,
              !buildVersion.isEmpty else { return false }
        guard let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !shortVersion.isEmpty else { return false }
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURL.isEmpty else { return false }
        guard let pubKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !pubKey.isEmpty else { return false }
        return true
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
        let message = (error as NSError).localizedDescription
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
        AppPresentation.promoteToForeground()
        startFloatingWindows()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        AppPresentation.promoteToForeground()
        startFloatingWindows()
    }

    func standardUserDriverWillFinishUpdateSession() {
        stopFloatingWindows()
        AppPresentation.returnToAccessory()
    }
}
