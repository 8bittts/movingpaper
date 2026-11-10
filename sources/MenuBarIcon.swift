import AppKit

/// Brand icon assets for MovingPaper.
/// The status item is a template SF Symbol so the system can tint it for light
/// and dark menu bars and the selected state (HIG: menu bar extras).
/// The colour night-sky PNG stays the app icon.
enum MenuBarIcon {
    /// Template glyph for `NSStatusItem`, at the symbol's own size. The glyph is
    /// wider than it is tall, so forcing a square size stretches it.
    static func brandIcon() -> NSImage {
        NSImage(systemSymbolName: "cloud.moon.fill", accessibilityDescription: "MovingPaper") ?? NSImage()
    }

    /// Full-resolution brand image suitable for `NSApp.applicationIconImage`.
    static func applicationIcon() -> NSImage? {
        Bundle.module
            .url(forResource: "movingpaper-icon", withExtension: "png", subdirectory: "Resources")
            .flatMap(NSImage.init(contentsOf:))
    }
}
