import AppKit
import Combine
@preconcurrency import Sparkle

/// Sparkle auto-updater wrapper for MovingPaper.
/// Uses Sparkle's standard UI (native macOS alerts) with activation policy
/// management for menu-bar-only apps.
@MainActor
final class MovingPaperUpdater: NSObject, ObservableObject {

    enum UpdateStatus: Equatable {
        case idle
        case checking
        case available(version: String)
        case upToDate
        case error(message: String)
    }

    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var canCheckForUpdates = false

    private var updaterController: SPUStandardUpdaterController?
    private var cancellables = Set<AnyCancellable>()
    private var started = false

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
            status = .error(message: "Updater failed to start: \(error.localizedDescription)")
        }
    }

    /// Trigger a manual update check (user-initiated).
    func checkForUpdates() {
        guard let controller = updaterController else {
            status = .error(message: "Updates unavailable in development builds.")
            return
        }

        status = .checking
        controller.updater.checkForUpdates()
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
        status = .available(version: version)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        status = .upToDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        status = .error(message: (error as NSError).localizedDescription)
    }
}

// MARK: - SPUStandardUserDriverDelegate

@MainActor
extension MovingPaperUpdater: @preconcurrency SPUStandardUserDriverDelegate {

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillFinishUpdateSession() {
        NSApp.setActivationPolicy(.accessory)
    }
}
