import Foundation
import Testing
@testable import MovingPaper

struct AppPathsTests {

    @Test func applicationSupportSitsUnderTheMovingPaperRoot() {
        #expect(AppPaths.applicationSupport.lastPathComponent == "MovingPaper")
    }

    @Test func cacheDirectoriesNestUnderApplicationSupport() {
        let root = AppPaths.applicationSupport
        #expect(AppPaths.youtubeCache.deletingLastPathComponent() == root)
        #expect(AppPaths.youtubeCache.lastPathComponent == "YouTube")
        #expect(AppPaths.photosPickerCache.deletingLastPathComponent() == root)
        #expect(AppPaths.photosPickerCache.lastPathComponent == "Photos")
        #expect(AppPaths.photosShuffleCache.deletingLastPathComponent() == root)
        #expect(AppPaths.photosShuffleCache.lastPathComponent == "PhotosShuffle")
    }

    @Test func ytdlpBinarySitsAtAppSupportRoot() {
        #expect(AppPaths.ytdlpBinary.deletingLastPathComponent() == AppPaths.applicationSupport)
        #expect(AppPaths.ytdlpBinary.lastPathComponent == "yt-dlp")
    }
}
