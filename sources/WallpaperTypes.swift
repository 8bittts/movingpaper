import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// How wallpapers are assigned.
enum WallpaperMode: String {
    case allDesktops
    case perDesktop
}

/// Composite key for per-desktop wallpaper assignments.
struct DesktopKey: Hashable {
    let displayID: CGDirectDisplayID
    let spaceID: UInt64

    /// Whether this is a display's all-desktops slot. Space ID 0 is that
    /// sentinel, never a real Space.
    var isAllDesktops: Bool { spaceID == 0 }

    /// The all-desktops slot of a display.
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

    /// The open panel's filter: exactly the extensions `detect` accepts.
    static let allowedContentTypes: [UTType] = ["gif", "mov", "mp4", "m4v"]
        .compactMap { UTType(filenameExtension: $0) }
}
