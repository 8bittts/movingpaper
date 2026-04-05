import AppKit
import SwiftUI

/// Manages a single WallpaperPanel for one screen.
/// Hosts either a video or GIF wallpaper view as its content.
@MainActor
final class WallpaperWindowController {
    let panel: WallpaperPanel
    let screen: NSScreen
    private var hostingView: NSHostingView<AnyView>?

    init(screen: NSScreen) {
        self.screen = screen
        self.panel = WallpaperPanel(screen: screen)
    }

    func show(content: some View) {
        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.frame = panel.contentView?.bounds ?? screen.frame
        hosting.autoresizingMask = [.width, .height]

        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
        panel.contentView?.addSubview(hosting)
        self.hostingView = hosting

        panel.orderFront(nil)
    }

    func reposition(to screen: NSScreen) {
        panel.setFrame(screen.frame, display: true)
    }

    func close() {
        panel.orderOut(nil)
    }
}
