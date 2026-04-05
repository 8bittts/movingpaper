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
        let size = menuBarSize
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.interpolationQuality = .high

            // Smooth continuous-curvature path (squircle) at 30% radius
            let radius = min(rect.width, rect.height) * 0.30
            let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.addPath(path)
            ctx.clip()

            // Draw the source image
            if let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(cgImage, in: rect)
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
