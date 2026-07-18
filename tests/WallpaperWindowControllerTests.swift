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
}
