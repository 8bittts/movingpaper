import Foundation
import Testing
@testable import MovingPaper

@Suite("YouTubeURLParser")
struct YouTubeURLParserTests {

    // MARK: - Standard watch URLs

    @Test func standardWatch() {
        #expect(YouTubeURLParser.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func watchWithExtraParams() {
        #expect(YouTubeURLParser.videoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42&list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf") == "dQw4w9WgXcQ")
    }

    @Test func watchNoWWW() {
        #expect(YouTubeURLParser.videoID(from: "https://youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func watchHTTP() {
        #expect(YouTubeURLParser.videoID(from: "http://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func mobileWatch() {
        #expect(YouTubeURLParser.videoID(from: "https://m.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    // MARK: - Short URLs

    @Test func shortURL() {
        #expect(YouTubeURLParser.videoID(from: "https://youtu.be/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func shortURLWithTimestamp() {
        #expect(YouTubeURLParser.videoID(from: "https://youtu.be/dQw4w9WgXcQ?t=120") == "dQw4w9WgXcQ")
    }

    // MARK: - Shorts

    @Test func shortsURL() {
        #expect(YouTubeURLParser.videoID(from: "https://www.youtube.com/shorts/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    // MARK: - Embed / v/ URLs

    @Test func embedURL() {
        #expect(YouTubeURLParser.videoID(from: "https://www.youtube.com/embed/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    @Test func vURL() {
        #expect(YouTubeURLParser.videoID(from: "https://www.youtube.com/v/dQw4w9WgXcQ") == "dQw4w9WgXcQ")
    }

    // MARK: - Edge cases

    @Test func idWithHyphensAndUnderscores() {
        #expect(YouTubeURLParser.videoID(from: "https://youtu.be/A_B-c1d2e3f") == "A_B-c1d2e3f")
    }

    @Test func whitespace() {
        #expect(YouTubeURLParser.videoID(from: "  https://youtu.be/dQw4w9WgXcQ  ") == "dQw4w9WgXcQ")
    }

    // MARK: - Invalid URLs

    @Test func emptyString() {
        #expect(YouTubeURLParser.videoID(from: "") == nil)
    }

    @Test func randomString() {
        #expect(YouTubeURLParser.videoID(from: "not a url at all") == nil)
    }

    @Test func otherDomain() {
        #expect(YouTubeURLParser.videoID(from: "https://vimeo.com/123456789") == nil)
    }

    @Test func tooShortID() {
        #expect(YouTubeURLParser.videoID(from: "https://youtu.be/short") == nil)
    }

    @Test func plainVideoID() {
        #expect(YouTubeURLParser.videoID(from: "dQw4w9WgXcQ") == nil)
    }

    // MARK: - isYouTubeURL

    @Test func isYouTubeValid() {
        #expect(YouTubeURLParser.isYouTubeURL("https://youtu.be/dQw4w9WgXcQ") == true)
    }

    @Test func isYouTubeInvalid() {
        #expect(YouTubeURLParser.isYouTubeURL("https://example.com") == false)
    }
}
