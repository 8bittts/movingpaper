import AppKit

/// Menu bar icon for Moving Paper.
/// Loads a pre-rounded brand image from the resource bundle.
@MainActor
enum MenuBarIcon {
    static let pointSize = NSSize(width: 22, height: 22)

    static func brandIcon() -> NSImage {
        // Load pre-rounded icon (corners baked into the PNG)
        if let url = Bundle.module.url(forResource: "moving-paper-icon", withExtension: "png", subdirectory: "Resources"),
           let img = NSImage(contentsOf: url) {
            img.size = pointSize
            img.isTemplate = false
            return img
        }

        let fallback = NSImage(systemSymbolName: "cloud.moon.fill", accessibilityDescription: "Moving Paper") ?? NSImage()
        fallback.size = pointSize
        return fallback
    }
}
