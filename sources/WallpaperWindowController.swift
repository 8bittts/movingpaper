import AppKit
import CoreMedia

/// Wallpaper content a `WallpaperWindowController` hosts. Both the video and GIF
/// views conform, so occlusion and power pausing cover every wallpaper type.
@MainActor
protocol WallpaperContentView: NSView {
    /// Stops rendering work while the wallpaper is hidden or the system is
    /// conserving power. Setting the current value again does nothing.
    var isPlaybackPaused: Bool { get set }
}

/// Manages a single WallpaperPanel for one screen.
/// Hosts an AppKit content view (video or GIF) directly — no SwiftUI bridge.
@MainActor
final class WallpaperWindowController {
    private let panel: WallpaperPanel
    private(set) var currentURL: URL?
    private var contentView: (any WallpaperContentView)?
    private var occlusionObserver: Any?
    private var isOccluded = false
    private var isPowerSuspended = false

    /// Current position of the hosted video, if this panel is showing one.
    var playbackTime: CMTime? {
        (contentView as? VideoWallpaperView)?.playbackTime
    }

    init(screen: NSScreen) {
        self.panel = WallpaperPanel(screen: screen)
        observeOcclusion()
    }

    /// Pause the content when the panel is fully occluded (e.g. a fullscreen app
    /// covers the desktop) so it isn't decoding frames nobody can see; resume
    /// when any part becomes visible again. `.visible` means *any* portion shows,
    /// so this only pauses when the wallpaper is entirely hidden.
    ///
    /// Only the notification updates `isOccluded`. A panel reads as not visible
    /// until the window server reports back, so sampling `occlusionState` right
    /// after `orderFront` would pause a wallpaper that is about to appear.
    private func observeOcclusion() {
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isOccluded = !self.panel.occlusionState.contains(.visible)
                self.applyPlaybackState()
            }
        }
    }

    func setPowerSuspended(_ suspended: Bool) {
        isPowerSuspended = suspended
        applyPlaybackState()
    }

    func setMuted(_ muted: Bool) {
        (contentView as? VideoWallpaperView)?.isMuted = muted
    }

    private func applyPlaybackState() {
        contentView?.isPlaybackPaused = isOccluded || isPowerSuspended
    }

    /// Install an AppKit view as the wallpaper content for this panel.
    func show(_ view: any WallpaperContentView, url: URL) {
        currentURL = url

        view.frame = panel.contentView?.bounds ?? panel.frame
        view.autoresizingMask = [.width, .height]

        contentView?.removeFromSuperview()
        panel.contentView?.addSubview(view)
        contentView = view

        panel.orderFront(nil)
        applyPlaybackState()
    }

    func reposition(to screen: NSScreen) {
        // Skip the (potentially display-forcing) reframe when nothing moved —
        // reconcile() calls this on every rebuild, including space switches.
        guard panel.frame != screen.frame else { return }
        panel.setFrame(screen.frame, display: true)
    }

    func close() {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        contentView?.removeFromSuperview()
        contentView = nil
        panel.orderOut(nil)
        panel.close()
    }
}
