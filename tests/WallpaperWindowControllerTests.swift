import AVFoundation
import Testing
@testable import MovingPaper

@MainActor
struct WallpaperWindowControllerTests {

    @Test func occlusionPausesWhenHiddenAndResumesWhenVisible() {
        let player = AVQueuePlayer()

        // Fully occluded → paused.
        WallpaperWindowController.applyOcclusion(isVisible: false, to: player)
        #expect(player.rate == 0)

        // Any part visible → playing.
        WallpaperWindowController.applyOcclusion(isVisible: true, to: player)
        #expect(player.rate == 1)

        // Back to occluded → paused again.
        WallpaperWindowController.applyOcclusion(isVisible: false, to: player)
        #expect(player.rate == 0)
    }

    @Test func occlusionIsANoOpWhenThereIsNoPlayer() {
        // GIF wallpapers have no player; must not crash.
        WallpaperWindowController.applyOcclusion(isVisible: false, to: nil)
        WallpaperWindowController.applyOcclusion(isVisible: true, to: nil)
    }
}
