import AppKit

/// Brand icon assets for MovingPaper.
/// The PNG is loaded once and reused for the menu bar item and the app icon.
@MainActor
enum MenuBarIcon {
    static let pointSize = NSSize(width: 22, height: 22)

    private static let cachedImage: NSImage? = Bundle.module
        .url(forResource: "movingpaper-icon", withExtension: "png", subdirectory: "Resources")
        .flatMap(NSImage.init(contentsOf:))

    /// Pre-rounded brand image sized for the status bar item.
    static func brandIcon() -> NSImage {
        if let cached = cachedImage {
            let copy = cached.copy() as? NSImage ?? cached
            copy.size = pointSize
            copy.isTemplate = false
            return copy
        }

        let fallback = NSImage(systemSymbolName: "cloud.moon.fill", accessibilityDescription: "MovingPaper") ?? NSImage()
        fallback.size = pointSize
        return fallback
    }

    /// Full-resolution brand image suitable for `NSApp.applicationIconImage`.
    static func applicationIcon() -> NSImage? {
        cachedImage.flatMap { $0.copy() as? NSImage }
    }
}
