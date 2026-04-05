import AppKit

/// Menu bar icon loader for Moving Paper.
/// Uses the brand pixel art image at menu bar size (26x26), same approach as Kindred.
@MainActor
enum MenuBarIcon {
    static let menuBarSize = NSSize(width: 26, height: 26)

    /// Load brand icon from the app resource bundle, scaled to menu bar size.
    /// Falls back to a system symbol if the brand image is missing.
    static func brandIcon() -> NSImage {
        // Try loading from the SPM resource bundle
        if let url = Bundle.module.url(forResource: "moving-paper", withExtension: "png", subdirectory: "Resources"),
           let source = NSImage(contentsOf: url) {
            return resized(source)
        }

        // Try loading from main bundle resources
        if let url = Bundle.main.url(forResource: "moving-paper", withExtension: "png"),
           let source = NSImage(contentsOf: url) {
            return resized(source)
        }

        // Fallback
        let fallback = NSImage(
            systemSymbolName: "cloud.moon.fill",
            accessibilityDescription: "Moving Paper"
        ) ?? NSImage()
        fallback.size = menuBarSize
        return fallback
    }

    private static func resized(_ source: NSImage) -> NSImage {
        let image = NSImage(size: menuBarSize, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            path.addClip()
            source.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }
}
