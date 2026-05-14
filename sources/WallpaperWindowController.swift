import AppKit
import AVFoundation

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

    init(screen: NSScreen) {
        self.screen = screen
        self.panel = WallpaperPanel(screen: screen)
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
        panel.setFrame(newScreen.frame, display: true)
    }

    func close() {
        contentView?.removeFromSuperview()
        contentView = nil
        panel.orderOut(nil)
        panel.close()
    }
}
