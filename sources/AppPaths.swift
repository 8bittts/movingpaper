import Foundation

/// Centralized filesystem locations for MovingPaper's caches and tools.
/// All paths live under `~/Library/Application Support/<rootName>/`.
enum AppPaths {
    private static let rootName = "MovingPaper"

    static var applicationSupport: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent(rootName, isDirectory: true)
    }

    /// Cache directory for downloaded YouTube videos.
    static var youtubeCache: URL {
        applicationSupport.appendingPathComponent("YouTube", isDirectory: true)
    }

    /// Cache directory for videos exported from Photos via the picker.
    static var photosPickerCache: URL {
        applicationSupport.appendingPathComponent("Photos", isDirectory: true)
    }

    /// Cache directory for randomly-shuffled Photos videos.
    static var photosShuffleCache: URL {
        applicationSupport.appendingPathComponent("PhotosShuffle", isDirectory: true)
    }

    /// On-disk location of the yt-dlp binary (downloaded on first use).
    static var ytdlpBinary: URL {
        applicationSupport.appendingPathComponent("yt-dlp")
    }
}
