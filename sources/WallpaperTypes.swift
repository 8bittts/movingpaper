import CoreGraphics
import Foundation

/// How wallpapers are assigned.
enum WallpaperMode: String {
    case allDesktops
    case perDesktop
}

/// Composite key for per-desktop wallpaper assignments.
struct DesktopKey: Hashable {
    let displayID: CGDirectDisplayID
    let spaceID: UInt64

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        self.spaceID = 0
    }

    init(displayID: CGDirectDisplayID, spaceID: UInt64) {
        self.displayID = displayID
        self.spaceID = spaceID
    }
}

enum WallpaperFileType {
    case gif
    case video

    static func detect(for url: URL) -> WallpaperFileType? {
        switch url.pathExtension.lowercased() {
        case "gif": return .gif
        case "mov", "mp4", "m4v": return .video
        default: return nil
        }
    }
}
