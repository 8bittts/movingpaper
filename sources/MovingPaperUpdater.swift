import AppKit
import Combine
@preconcurrency import Sparkle

/// Sparkle auto-updater wrapper for MovingPaper.
/// Checks for updates via an appcast feed and handles EdDSA-signed releases.
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
    private let presentationCoordinator = SparklePresentationCoordinator()

    override init() {
        super.init()

        // Sparkle requires a valid app bundle with SUFeedURL + SUPublicEDKey.
        // In dev (swift run), these are missing — updater stays dormant.
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
        presentationCoordinator.beginUserInitiatedCheck()
        status = .checking
        controller.updater.checkForUpdates()
    }

    // MARK: - Host Validation

    nonisolated private static func hostHasSparkleConfig() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier,
              !bundleID.isEmpty else { return false }
        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURL.isEmpty else { return false }
        guard let pubKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !pubKey.isEmpty else { return false }
        return true
    }
}

// MARK: - SPUUpdaterDelegate

@MainActor
extension MovingPaperUpdater: @preconcurrency SPUUpdaterDelegate {

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString.isEmpty
            ? item.versionString
            : item.displayVersionString
        status = .available(version: version)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        status = .upToDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        guard case .checking = status else { return }
        status = .error(message: (error as NSError).localizedDescription)
    }
}

// MARK: - SPUStandardUserDriverDelegate

@MainActor
extension MovingPaperUpdater: @preconcurrency SPUStandardUserDriverDelegate {

    func standardUserDriverWillShowModalAlert() {
        presentationCoordinator.willShowModalAlert()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        presentationCoordinator.willShowUpdate()
    }

    func standardUserDriverWillFinishUpdateSession() {
        presentationCoordinator.finishUpdateSession()
    }
}
