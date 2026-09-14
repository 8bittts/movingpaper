import AppKit

/// Brand icon assets for MovingPaper.
/// The status item is a template SF Symbol so the system can tint it for light
/// and dark menu bars and the selected state (HIG: menu bar extras).
/// The colour night-sky PNG stays the app icon.
@MainActor
enum MenuBarIcon {
    static let pointSize = NSSize(width: 18, height: 18)

    private static let cachedImage: NSImage? = Bundle.module
        .url(forResource: "movingpaper-icon", withExtension: "png", subdirectory: "Resources")
        .flatMap(NSImage.init(contentsOf:))

    /// Template glyph for `NSStatusItem`. Black-and-clear; the system applies colour.
    static func brandIcon() -> NSImage {
        let image = NSImage(systemSymbolName: "cloud.moon.fill", accessibilityDescription: "MovingPaper")
            ?? NSImage()
        image.size = pointSize
        image.isTemplate = true
        return image
    }

    /// Full-resolution brand image suitable for `NSApp.applicationIconImage`.
    static func applicationIcon() -> NSImage? {
        cachedImage.flatMap { $0.copy() as? NSImage }
    }
}
