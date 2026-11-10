import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import MovingPaper

/// The video and GIF views a wallpaper panel hosts. Everything here runs
/// without a window, so no wallpaper appears on the desktop.
@MainActor
struct WallpaperContentViewTests {

    private static let samples = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "videos")
    private static let sampleVideo = samples.appending(path: "test-01.mp4")
    private static let sampleGIF = samples.appending(path: "test-00.gif")

    // MARK: - Video

    /// Low Power Mode or an occluding window can pause the view before the asset
    /// has loaded. The player that arrives later must not start on its own.
    @Test func videoLoadedWhilePausedStaysPaused() async {
        let view = VideoWallpaperView(frame: .zero)
        view.isPlaybackPaused = true
        view.loadVideo(url: Self.sampleVideo)
        await view.loadTask?.value
        #expect(!view.isPlaying)

        view.isPlaybackPaused = false
        #expect(view.isPlaying)
    }

    @Test func videoLoadedWhileVisiblePlays() async {
        let view = VideoWallpaperView(frame: .zero)
        view.loadVideo(url: Self.sampleVideo)
        await view.loadTask?.value
        #expect(view.isPlaying)

        view.isPlaybackPaused = true
        #expect(!view.isPlaying)
    }

    @Test func unreadableVideoIsReported() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "movingpaper-unreadable-\(UUID().uuidString).mp4")
        try Data("not a movie".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        var reported: String?
        let view = VideoWallpaperView(frame: .zero)
        view.onFailure = { _, message in reported = message }
        view.loadVideo(url: url)
        await view.loadTask?.value

        #expect(reported != nil)
        #expect(!view.isPlaying)
    }

    @Test func missingVideoIsReported() async {
        var reported: String?
        let view = VideoWallpaperView(frame: .zero)
        view.onFailure = { _, message in reported = message }
        view.loadVideo(url: URL(filePath: "/tmp/movingpaper-missing-\(UUID().uuidString).mp4"))
        await view.loadTask?.value
        #expect(reported != nil)
    }

    /// A newer load supersedes the one in flight, so the stale asset never installs.
    @Test func removingTheViewCancelsALoadInFlight() async {
        let view = VideoWallpaperView(frame: .zero)
        view.loadVideo(url: Self.sampleVideo)
        let load = view.loadTask
        view.removeFromSuperview()
        await load?.value
        #expect(view.loadTask == nil)
        #expect(!view.isPlaying)
    }

    // MARK: - GIF

    /// The router re-applies the pause state on every reconcile. Re-applying
    /// "not paused" must not restart a GIF that is already animating.
    @Test func reapplyingTheSamePauseStateDoesNotRestartAGIF() {
        let gif = GIFWallpaperView(frame: .zero)
        gif.loadGIF(url: Self.sampleGIF)
        let generation = gif.animationGeneration

        gif.isPlaybackPaused = false
        #expect(gif.animationGeneration == generation)

        gif.isPlaybackPaused = true
        gif.isPlaybackPaused = true
        #expect(gif.animationGeneration == generation + 1)

        gif.isPlaybackPaused = false
        #expect(gif.animationGeneration == generation + 2)
    }

    @Test func gifLoadedWhilePausedShowsItsFirstFrameWithoutAnimating() {
        let gif = GIFWallpaperView(frame: .zero)
        gif.isPlaybackPaused = true
        gif.loadGIF(url: Self.sampleGIF)
        #expect(gif.hasVisibleContents)
        #expect(gif.currentURL == Self.sampleGIF)
    }

    @Test func gifPauseIsSafeWithNothingLoaded() {
        let gif = GIFWallpaperView(frame: .zero)
        gif.isPlaybackPaused = true
        gif.isPlaybackPaused = false
        #expect(gif.currentURL == nil)
    }

    @Test func gifPauseKeepsTheLastFrameVisible() {
        let gif = GIFWallpaperView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        gif.displayFrame(Self.makePixel())
        #expect(gif.hasVisibleContents)
        gif.isPlaybackPaused = true
        #expect(gif.hasVisibleContents)
    }

    @Test(arguments: [false, true])
    func gifLoadFailureOnAMissingFileIsReported(paused: Bool) {
        var reported: String?
        let gif = GIFWallpaperView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        gif.onFailure = { _, message in reported = message }
        gif.isPlaybackPaused = paused
        gif.loadGIF(url: URL(filePath: "/tmp/movingpaper-missing-\(UUID().uuidString).gif"))
        #expect(reported != nil)
        #expect(gif.currentURL == nil)
    }

    @Test func gifPlaybackMessageCoversImageIOStatusCodes() {
        #expect(
            GIFWallpaperView.playbackMessage(status: CGImageAnimationStatus.corruptInputImage.rawValue)
                == "The GIF file is unreadable."
        )
        #expect(
            GIFWallpaperView.playbackMessage(status: CGImageAnimationStatus.unsupportedFormat.rawValue)
                == "That image format cannot be animated."
        )
        #expect(GIFWallpaperView.playbackMessage(status: 0) == "The GIF could not be played.")
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
