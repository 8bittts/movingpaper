import AppKit

/// Menu bar icon loader for Moving Paper.
@MainActor
enum MenuBarIcon {

    static func brandIcon() -> NSImage {
        let pointSize = NSSize(width: 22, height: 22)
        let pixelScale = 2  // Retina
        let px = pixelScale * Int(pointSize.width)

        // Load source
        let source: NSImage? = {
            if let url = Bundle.module.url(forResource: "moving-paper", withExtension: "png", subdirectory: "Resources"),
               let img = NSImage(contentsOf: url) { return img }
            if let url = Bundle.main.url(forResource: "moving-paper", withExtension: "png"),
               let img = NSImage(contentsOf: url) { return img }
            return nil
        }()

        guard let source,
              let cgSource = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let fallback = NSImage(systemSymbolName: "cloud.moon.fill", accessibilityDescription: "Moving Paper") ?? NSImage()
            fallback.size = pointSize
            return fallback
        }

        // Render at 2x pixel resolution for crisp Retina corners
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = pointSize

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext

        cg.setShouldAntialias(true)
        cg.setAllowsAntialiasing(true)
        cg.interpolationQuality = .high

        let rect = CGRect(x: 0, y: 0, width: px, height: px)
        let radius = CGFloat(px) * 0.24
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        cg.addPath(path)
        cg.clip()
        cg.draw(cgSource, in: rect)

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }
}
