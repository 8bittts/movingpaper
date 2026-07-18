import AppKit
import AVFoundation

/// Content views that can cheaply pause/resume expensive rendering when their
/// hosting panel becomes fully occluded or visible again. Both the video and GIF
/// wallpaper views conform so occlusion power-saving covers every wallpaper type.
@MainActor
protocol OcclusionPausable: AnyObject {
    func setOcclusionHidden(_ hidden: Bool)
}

/// Manages a single WallpaperPanel for one screen.
/// Hosts an AppKit content view (video or GIF) directly — no SwiftUI bridge.
@MainActor
final class WallpaperWindowController {
    let panel: WallpaperPanel
    private(set) var screen: NSScreen
    private(set) var currentURL: URL?
    /// Direct reference to the video player for position save/restore and mute.
    var player: AVQueuePlayer?
    private var contentView: NSView?
    private var occlusionObserver: Any?

    init(screen: NSScreen) {
        self.screen = screen
        self.panel = WallpaperPanel(screen: screen)
        observeOcclusion()
    }

    /// Pause the video when the panel is fully occluded (e.g. a fullscreen app
    /// covers the desktop) so it isn't decoding frames nobody can see; resume
    /// when any part becomes visible again. `.visible` means *any* portion shows,
    /// so this only pauses when the wallpaper is entirely hidden.
    private func observeOcclusion() {
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Self.applyOcclusion(
                    isVisible: self.panel.occlusionState.contains(.visible),
                    to: self.contentView as? OcclusionPausable
                )
            }
        }
    }

    /// Pause the content when the wallpaper is fully hidden; resume when any part is
    /// visible. Routes through the content view (video *and* GIF) rather than the
    /// player directly, so GIF wallpapers pause too. Split out so the play/pause
    /// policy is unit-testable without the window server.
    static func applyOcclusion(isVisible: Bool, to pausable: OcclusionPausable?) {
        pausable?.setOcclusionHidden(!isVisible)
    }

    /// Install an AppKit view as the wallpaper content for this panel.
    func show(_ view: NSView, url: URL) {
        self.currentURL = url

        view.frame = panel.contentView?.bounds ?? screen.frame
        view.autoresizingMask = [.width, .height]

        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
        panel.contentView?.addSubview(view)
        self.contentView = view

        panel.orderFront(nil)
    }

    func reposition(to newScreen: NSScreen) {
        self.screen = newScreen
        // Skip the (potentially display-forcing) reframe when nothing moved —
        // reconcile() calls this on every rebuild, including space switches.
        guard panel.frame != newScreen.frame else { return }
        panel.setFrame(newScreen.frame, display: true)
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
