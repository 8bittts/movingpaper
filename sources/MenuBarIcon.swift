import AppKit

/// The menu-bar mark. The app icon is not code: it is the Icon Composer
/// document the build scripts compile into the bundle.
enum MenuBarIcon {
    /// Template glyph for `NSStatusItem`, at the symbol's own size, so the system
    /// tints it for light and dark menu bars and the selected state (HIG: menu
    /// bar extras). The glyph is wider than it is tall, so forcing a square size
    /// stretches it.
    static func brandIcon() -> NSImage {
        NSImage(systemSymbolName: "cloud.moon.fill", accessibilityDescription: "MovingPaper") ?? NSImage()
    }
}
