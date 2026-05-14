import AppKit
import QuartzCore

/// Brand icon assets for MovingPaper.
/// The PNG is loaded once and reused for the menu bar item and the app icon.
/// Corner rounding uses `CALayer.cornerCurve = .continuous` so the menu bar
/// item shape matches the macOS Big Sur+ app-icon squircle exactly — the same
/// continuous-curvature shape DockishOS gets from its baked `.icns`.
@MainActor
enum MenuBarIcon {
    static let pointSize = NSSize(width: 22, height: 22)
    /// macOS app-icon continuous-corner radius ratio. Combined with
    /// `cornerCurve = .continuous`, this produces the standard squircle.
    private static let cornerRadiusRatio: CGFloat = 0.225

    private static let cachedImage: NSImage? = Bundle.module
        .url(forResource: "movingpaper-icon", withExtension: "png", subdirectory: "Resources")
        .flatMap(NSImage.init(contentsOf:))

    /// Brand image sized for the status bar, clipped to a continuous-corner
    /// squircle so the menu bar item matches the macOS app-icon shape
    /// regardless of the source PNG's own (limited) rounded corners.
    static func brandIcon() -> NSImage {
        guard let source = cachedImage else { return fallbackIcon() }
        return squircleClipped(source: source, size: pointSize, radiusRatio: cornerRadiusRatio)
    }

    /// Full-resolution brand image suitable for `NSApp.applicationIconImage`.
    static func applicationIcon() -> NSImage? {
        cachedImage.flatMap { $0.copy() as? NSImage }
    }

    /// Render `source` into a fresh `NSImage` masked by a `CALayer` whose
    /// `cornerCurve = .continuous` produces a true macOS squircle (the curve
    /// blends smoothly along the edge instead of meeting it tangentially like
    /// `NSBezierPath(roundedRect:)` does). The mask is applied via
    /// `layer.render(in:)` so the geometry is baked into pixels at draw time.
    private static func squircleClipped(source: NSImage, size: NSSize, radiusRatio: CGFloat) -> NSImage {
        guard let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let fallback = source.copy() as? NSImage ?? source
            fallback.size = size
            fallback.isTemplate = false
            return fallback
        }

        return NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            let layer = CALayer()
            layer.frame = rect
            layer.contents = cgImage
            layer.contentsGravity = .resizeAspectFill
            layer.cornerRadius = min(rect.width, rect.height) * radiusRatio
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
            layer.isGeometryFlipped = true

            layer.render(in: context)
            return true
        }
    }

    private static func fallbackIcon() -> NSImage {
        let fallback = NSImage(systemSymbolName: "cloud.moon.fill", accessibilityDescription: "MovingPaper") ?? NSImage()
        fallback.size = pointSize
        return fallback
    }
}
