import AppKit

/// Brand icon assets for MovingPaper.
/// The PNG is loaded once and reused for the menu bar item and the app icon.
@MainActor
enum MenuBarIcon {
    static let pointSize = NSSize(width: 22, height: 22)
    /// Rounded-rect approximation of the macOS Big Sur+ "squircle" app icon
    /// shape. AppKit doesn't expose a continuous-corner path, so we use a
    /// slightly larger ratio than the geometric 22 % so the rounded rectangle
    /// reads visually as rounded as the true squircle (e.g. DockishOS).
    private static let cornerRadiusRatio: CGFloat = 0.32

    private static let cachedImage: NSImage? = Bundle.module
        .url(forResource: "movingpaper-icon", withExtension: "png", subdirectory: "Resources")
        .flatMap(NSImage.init(contentsOf:))

    /// Brand image sized for the status bar, with a rounded-rect clip applied so
    /// corner rounding matches macOS app icons regardless of the source PNG.
    static func brandIcon() -> NSImage {
        guard let source = cachedImage else { return fallbackIcon() }
        return roundedImage(source: source, size: pointSize, radiusRatio: cornerRadiusRatio)
    }

    /// Full-resolution brand image suitable for `NSApp.applicationIconImage`.
    static func applicationIcon() -> NSImage? {
        cachedImage.flatMap { $0.copy() as? NSImage }
    }

    private static func roundedImage(source: NSImage, size: NSSize, radiusRatio: CGFloat) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let radius = min(rect.width, rect.height) * radiusRatio
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
            source.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func fallbackIcon() -> NSImage {
        let fallback = NSImage(systemSymbolName: "cloud.moon.fill", accessibilityDescription: "MovingPaper") ?? NSImage()
        fallback.size = pointSize
        return fallback
    }
}
