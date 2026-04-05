import AppKit
import Combine

/// Central coordinator: manages per-screen wallpaper windows, file selection,
/// playback state, and power-aware pause/resume.
@MainActor
final class WallpaperManager: ObservableObject {
    @Published var currentFileURL: URL?
    @Published var isPaused: Bool = false
    @Published var isPerScreen: Bool = false  // future: per-monitor files

    private var controllers: [CGDirectDisplayID: WallpaperWindowController] = [:]
    private var screenObserver: Any?
    private var occlusionObservers: [Any] = []
    private var powerObservers: [Any] = []
    private var systemPaused: Bool = false  // paused by system (thermal/battery)

    init() {
        observeScreenChanges()
        observePowerState()
    }

    // MARK: - File Selection

    var currentFileName: String? {
        currentFileURL?.lastPathComponent
    }

    var fileType: WallpaperFileType? {
        guard let ext = currentFileURL?.pathExtension.lowercased() else { return nil }
        switch ext {
        case "gif":
            return .gif
        case "mov", "mp4", "m4v":
            return .video
        default:
            return nil
        }
    }

    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .gif, .mpeg4Movie, .quickTimeMovie, .movie,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a GIF or video file for your desktop wallpaper"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        setWallpaper(url: url)
    }

    func setWallpaper(url: URL) {
        currentFileURL = url
        isPaused = false
        rebuildAllWindows()
    }

    func clearWallpaper() {
        currentFileURL = nil
        tearDown()
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            tearDownWindows()
        } else {
            rebuildAllWindows()
        }
    }

    // MARK: - Window Lifecycle

    func rebuildAllWindows() {
        tearDownWindows()
        guard let url = currentFileURL, !isPaused else { return }

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let controller = WallpaperWindowController(screen: screen)

            switch fileType {
            case .video:
                controller.show(content: VideoWallpaperView(url: url))
            case .gif:
                controller.show(content: GIFWallpaperView(url: url))
            case nil:
                continue
            }

            controllers[displayID] = controller
            observeOcclusion(for: controller)
        }
    }

    func tearDown() {
        tearDownWindows()
        removeScreenObserver()
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
        occlusionObservers.removeAll()
    }

    // MARK: - Screen Changes

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildAllWindows()
            }
        }
    }

    private func removeScreenObserver() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }

    // MARK: - Power Management

    private func observePowerState() {
        // Low Power Mode (macOS 12+)
        let lowPower = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evaluatePowerState()
            }
        }
        powerObservers.append(lowPower)

        // Thermal state changes
        let thermal = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evaluatePowerState()
            }
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

    private func observeOcclusion(for controller: WallpaperWindowController) {
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: controller.panel,
            queue: .main
        ) { notification in
            // Desktop-level windows are automatically deprioritized by the
            // compositor when fully occluded (fullscreen app). AVPlayer and
            // CGAnimateImage both respect CALayer visibility. No manual
            // pause needed — the system handles it.
        }
        occlusionObservers.append(observer)
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
