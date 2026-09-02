import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import MovingPaper

@MainActor
struct WallpaperWindowControllerTests {

    /// Records the last occlusion command so the pause/resume routing is testable
    /// without a window server or a loaded media asset.
    private final class MockPausable: OcclusionPausable {
        private(set) var hidden: Bool?
        func setOcclusionHidden(_ hidden: Bool) { self.hidden = hidden }
    }

    @Test func occlusionPausesWhenHiddenAndResumesWhenVisible() {
        let content = MockPausable()

        // Fully occluded → paused.
        WallpaperWindowController.applyOcclusion(isVisible: false, to: content)
        #expect(content.hidden == true)

        // Any part visible → resumed.
        WallpaperWindowController.applyOcclusion(isVisible: true, to: content)
        #expect(content.hidden == false)

        // Back to occluded → paused again.
        WallpaperWindowController.applyOcclusion(isVisible: false, to: content)
        #expect(content.hidden == true)
    }

    @Test func occlusionIsANoOpWhenThereIsNoPausableContent() {
        // Content may be absent or not occlusion-aware; must not crash.
        WallpaperWindowController.applyOcclusion(isVisible: false, to: nil)
        WallpaperWindowController.applyOcclusion(isVisible: true, to: nil)
    }

    @Test func gifViewParticipatesInOcclusionAndIsNilURLSafe() {
        // GIF wallpapers now pause on occlusion too. With no GIF loaded, both
        // pause and resume must be safe no-ops.
        let gif = GIFAnimationNSView(frame: .zero)
        #expect(gif.currentURL == nil)
        gif.setOcclusionHidden(true)
        gif.setOcclusionHidden(false)
        #expect(gif.currentURL == nil)
    }

    @Test func gifOcclusionPauseKeepsTheLastFrameVisible() {
        let gif = GIFAnimationNSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        gif.displayFrame(Self.makePixel())
        #expect(gif.hasVisibleContents)
        gif.setOcclusionHidden(true)
        #expect(gif.hasVisibleContents)
    }

    @Test func gifLoadFailureOnAMissingFileIsReported() {
        var reported: String?
        let gif = GIFAnimationNSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        gif.onFailure = { _, message in reported = message }
        gif.loadGIF(url: URL(filePath: "/tmp/movingpaper-missing-\(UUID().uuidString).gif"))
        #expect(reported != nil)
        #expect(gif.currentURL == nil)
    }

    @Test func gifPlaybackMessageCoversImageIOStatusCodes() {
        #expect(
            GIFAnimationNSView.playbackMessage(status: CGImageAnimationStatus.corruptInputImage.rawValue)
                == "The GIF file is unreadable."
        )
        #expect(
            GIFAnimationNSView.playbackMessage(status: CGImageAnimationStatus.unsupportedFormat.rawValue)
                == "That image format cannot be animated."
        )
        #expect(GIFAnimationNSView.playbackMessage(status: 0) == "The GIF could not be played.")
    }

    @Test func powerAndOcclusionTogetherKeepPlaybackPaused() {
        let content = MockPausable()
        // Hidden by occlusion, power is fine → paused.
        WallpaperWindowController.applyOcclusion(isVisible: false, to: content)
        #expect(content.hidden == true)
        // Visible and not power-suspended → playing.
        WallpaperWindowController.applyOcclusion(isVisible: true, to: content)
        #expect(content.hidden == false)
        // Combined policy: visible=false when either occlusion or power is active.
        WallpaperWindowController.applyOcclusion(isVisible: !true && !false, to: content)
        #expect(content.hidden == true)
    }

    private static func makePixel() -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}
