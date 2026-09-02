import AppKit
import CoreGraphics

/// Borderless panel that sits at the desktop level, behind icons but above the wallpaper.
/// Invisible to mouse events so Finder desktop icons remain fully interactive.
final class WallpaperPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Place between desktop background and desktop icons
        let desktopLevel = CGWindowLevelForKey(.desktopWindow)
        self.level = NSWindow.Level(rawValue: Int(desktopLevel) + 1)

        // Not opaque so HEVC-with-alpha and transparent GIFs still composite.
        // Black fill hides the system desktop during the first-frame wait so
        // a load hitch cannot flash through the panel.
        self.isOpaque = false
        self.backgroundColor = .black
        self.hasShadow = false
        self.isMovable = false
        self.ignoresMouseEvents = true
        self.isReleasedWhenClosed = false

        self.collectionBehavior = [
            .canJoinAllSpaces,   // Visible on all Spaces/desktops
            .stationary,         // Mission Control doesn't move it
            .ignoresCycle,       // Not in Cmd+` window cycle
            .fullScreenAuxiliary,
        ]
    }

    // NSPanel cannot become key or main — pure display surface
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
