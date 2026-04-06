import AppKit
import AVFoundation
import SwiftUI

/// Manages a single WallpaperPanel for one screen.
/// Hosts either a video or GIF wallpaper view as its content.
@MainActor
final class WallpaperWindowController {
    let panel: WallpaperPanel
    private(set) var screen: NSScreen
    private(set) var currentURL: URL?
    /// Direct reference to the video player for position save/restore and mute.
    var player: AVQueuePlayer?
    private var hostingView: NSHostingView<AnyView>?

    init(screen: NSScreen) {
        self.screen = screen
        self.panel = WallpaperPanel(screen: screen)
    }

    func show(content: some View, url: URL) {
        self.currentURL = url

        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.frame = panel.contentView?.bounds ?? screen.frame
        hosting.autoresizingMask = [.width, .height]

        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
        panel.contentView?.addSubview(hosting)
        self.hostingView = hosting

        panel.orderFront(nil)
    }

    func reposition(to newScreen: NSScreen) {
        self.screen = newScreen
        panel.setFrame(newScreen.frame, display: true)
    }

    func close() {
        hostingView?.removeFromSuperview()
        hostingView = nil
        panel.orderOut(nil)
        panel.close()
    }
}
