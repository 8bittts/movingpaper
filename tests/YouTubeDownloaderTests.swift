import Foundation
import Testing
@testable import MovingPaper

struct YouTubeDownloaderTests {

    /// Known-answer test: SHA-256 of the empty input is well-defined.
    @Test func sha256OfEmptyDataMatchesKnownAnswer() {
        let digest = YouTubeDownloader.sha256Hex(of: Data())
        #expect(digest == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func sha256OfAsciiInputMatchesKnownAnswer() {
        let digest = YouTubeDownloader.sha256Hex(of: Data("abc".utf8))
        #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func pinnedYTDLPVersionAndHashAreNotEmpty() {
        #expect(!YouTubeDownloader.pinnedYTDLPVersion.isEmpty)
        #expect(YouTubeDownloader.pinnedYTDLPSHA256.count == 64)
    }

    @Test @MainActor func invalidURLReturnsFailureOutcomeNotSuccess() async {
        let downloader = YouTubeDownloader()
        let outcome = await downloader.download(youtubeURL: "https://example.com/not-youtube")
        #expect(outcome == .failure("Invalid YouTube URL"))
    }
}
