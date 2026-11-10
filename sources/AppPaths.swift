import Foundation

/// Centralized filesystem locations for MovingPaper's caches and tools.
/// All paths live under `~/Library/Application Support/<rootName>/`.
enum AppPaths {
    private static let rootName = "MovingPaper"

    static var applicationSupport: URL {
        URL.applicationSupportDirectory.appending(path: rootName, directoryHint: .isDirectory)
    }

    /// Cache directory for downloaded YouTube videos.
    static var youtubeCache: URL {
        applicationSupport.appending(path: "YouTube", directoryHint: .isDirectory)
    }

    /// Cache directory for videos exported from Photos via the picker.
    static var photosPickerCache: URL {
        applicationSupport.appending(path: "Photos", directoryHint: .isDirectory)
    }

    /// Cache directory for randomly-shuffled Photos videos.
    static var photosShuffleCache: URL {
        applicationSupport.appending(path: "PhotosShuffle", directoryHint: .isDirectory)
    }

    /// On-disk location of the yt-dlp binary (downloaded on first use).
    static var ytdlpBinary: URL {
        applicationSupport.appending(path: "yt-dlp", directoryHint: .notDirectory)
    }
}
