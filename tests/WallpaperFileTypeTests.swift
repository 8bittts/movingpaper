import Testing
import Foundation
@testable import MovingPaper

/// Tests for wallpaper file type detection logic.
struct WallpaperFileTypeTests {

    @Test func gifDetection() {
        let url = URL(fileURLWithPath: "/tmp/test.gif")
        #expect(WallpaperFileType.detect(for: url) == .gif)
    }

    @Test func gifDetectionUppercase() {
        let url = URL(fileURLWithPath: "/tmp/test.GIF")
        #expect(WallpaperFileType.detect(for: url) == .gif)
    }

    @Test func mp4Detection() {
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        #expect(WallpaperFileType.detect(for: url) == .video)
    }

    @Test func movDetection() {
        let url = URL(fileURLWithPath: "/tmp/test.mov")
        #expect(WallpaperFileType.detect(for: url) == .video)
    }

    @Test func m4vDetection() {
        let url = URL(fileURLWithPath: "/tmp/test.m4v")
        #expect(WallpaperFileType.detect(for: url) == .video)
    }

    @Test func unsupportedFormat() {
        let url = URL(fileURLWithPath: "/tmp/test.png")
        #expect(WallpaperFileType.detect(for: url) == nil)
    }

    @Test func noExtension() {
        let url = URL(fileURLWithPath: "/tmp/wallpaper")
        #expect(WallpaperFileType.detect(for: url) == nil)
    }
}
