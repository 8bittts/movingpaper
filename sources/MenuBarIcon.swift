import AppKit

/// The menu-bar mark: the app's own icon, so the status item carries the brand
/// while MovingPaper runs. The icon itself is not code; it is the Icon Composer
/// document the build scripts compile into the bundle.
enum MenuBarIcon {
    /// The app icon includes its own margin, so a 22-point canvas draws a mark
    /// about as tall as a standard menu-bar glyph.
    static let pointSize = NSSize(width: 22, height: 22)

    /// The system-rendered app icon at menu-bar size. An unbundled run
    /// (`swift run`, the test runner) has no icon of its own, so it gets a
    /// template SF Symbol instead of the generic application icon.
    static func brandIcon(bundle: Bundle = .main) -> NSImage {
        guard bundle.object(forInfoDictionaryKey: "CFBundleIconName") != nil,
              let icon = NSImage(named: NSImage.applicationIconName)?.copy() as? NSImage
        else {
            return NSImage(systemSymbolName: "cloud.moon.fill", accessibilityDescription: "MovingPaper") ?? NSImage()
        }
        icon.size = pointSize
        icon.isTemplate = false
        icon.accessibilityDescription = "MovingPaper"
        return icon
    }
}
