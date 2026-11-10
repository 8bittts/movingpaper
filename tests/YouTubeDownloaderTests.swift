import Foundation
import Testing
@testable import MovingPaper

/// Drives `YouTubeDownloader` with a shell script standing in for yt-dlp, so the
/// subprocess, progress, cancellation and cleanup paths run with no network.
@MainActor
struct YouTubeDownloaderTests {

    private static let videoURL = "https://youtu.be/dQw4w9WgXcQ"
    private static let videoID = "dQw4w9WgXcQ"

    /// A scratch cache directory plus a fake yt-dlp built from `body`.
    /// The script sees the `-o` output path as `$out`.
    private final class Sandbox {
        let cache: URL
        let binary: URL
        private let root: URL

        init(script body: String) throws {
            root = FileManager.default.temporaryDirectory
                .appending(path: "movingpaper-ytdlp-\(UUID().uuidString)")
            cache = root.appending(path: "cache")
            binary = root.appending(path: "fake-yt-dlp")
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            let script = """
            #!/bin/sh
            while [ $# -gt 0 ]; do
              if [ "$1" = "-o" ]; then out="$2"; fi
              shift
            done
            \(body)
            """
            try Data(script.utf8).write(to: binary)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: binary.path(percentEncoded: false)
            )
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        @MainActor func makeDownloader() -> YouTubeDownloader {
            let path = binary.path(percentEncoded: false)
            return YouTubeDownloader(cacheDirectory: cache, resolveBinary: { path })
        }

        var cachedNames: [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: cache.path(percentEncoded: false))) ?? []).sorted()
        }
    }

    /// Suspend until `condition` holds; fails the test instead of hanging.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() {
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(condition())
    }

    // MARK: - Outcomes

    @Test func invalidURLFailsWithoutRunningAnything() async {
        let downloader = YouTubeDownloader(
            cacheDirectory: FileManager.default.temporaryDirectory,
            resolveBinary: { nil }
        )
        let outcome = await downloader.download(youtubeURL: "https://example.com/not-youtube")
        #expect(outcome == .failure("Invalid YouTube URL"))
    }

    @Test func missingBinaryFailsWithAnInstallMessage() async throws {
        let sandbox = try Sandbox(script: "exit 0")
        let downloader = YouTubeDownloader(cacheDirectory: sandbox.cache, resolveBinary: { nil })
        let outcome = await downloader.download(youtubeURL: Self.videoURL)
        #expect(outcome == .failure("Could not download yt-dlp. Check your internet connection."))
    }

    @Test func successReturnsTheCachedFileAndReportsProgress() async throws {
        // The script holds at 42% until the test releases it, so the progress
        // report is observed and never raced against the exit.
        let sandbox = try Sandbox(script: """
        echo "[download]  42.0% of 1.00MiB"
        while [ ! -e "$out.release" ]; do sleep 0.02; done
        : > "$out"
        """)
        let downloader = sandbox.makeDownloader()
        var reported: [Double?] = []

        let task = Task { @MainActor in
            await downloader.download(youtubeURL: Self.videoURL) { reported.append($0) }
        }
        try await waitUntil { downloader.progress == 0.42 }
        let expected = sandbox.cache.appending(path: "\(Self.videoID).mp4")
        FileManager.default.createFile(atPath: expected.path(percentEncoded: false) + ".release", contents: nil)

        let outcome = await task.value
        #expect(outcome == .success(expected))
        #expect(reported == [0, 0.42, nil])
        #expect(downloader.progress == nil)
    }

    @Test func aCachedVideoIsReturnedWithoutRunningTheBinary() async throws {
        let sandbox = try Sandbox(script: "exit 9")
        let cached = sandbox.cache.appending(path: "\(Self.videoID).mp4")
        FileManager.default.createFile(atPath: cached.path(percentEncoded: false), contents: nil)
        var reported: [Double?] = []

        let outcome = await sandbox.makeDownloader().download(youtubeURL: Self.videoURL) { reported.append($0) }

        #expect(outcome == .success(cached))
        #expect(reported.isEmpty)
    }

    @Test func failureSurfacesTheErrorLineAndRemovesIntermediates() async throws {
        let sandbox = try Sandbox(script: """
        : > "$out.part"
        echo "WARNING: something minor" >&2
        echo "ERROR: Video unavailable" >&2
        exit 1
        """)
        let outcome = await sandbox.makeDownloader().download(youtubeURL: Self.videoURL)
        #expect(outcome == .failure("Video unavailable"))
        #expect(sandbox.cachedNames.isEmpty)
    }

    @Test func aCleanExitWithoutAnOutputFileIsAFailure() async throws {
        let sandbox = try Sandbox(script: "exit 0")
        let outcome = await sandbox.makeDownloader().download(youtubeURL: Self.videoURL)
        #expect(outcome == .failure("Download completed but file not found"))
    }

    @Test func aBinaryThatCannotLaunchIsAFailure() async throws {
        let sandbox = try Sandbox(script: "exit 0")
        let downloader = YouTubeDownloader(
            cacheDirectory: sandbox.cache,
            resolveBinary: { "/nonexistent/movingpaper-yt-dlp" }
        )
        guard case .failure(let message) = await downloader.download(youtubeURL: Self.videoURL) else {
            Issue.record("expected a launch failure")
            return
        }
        #expect(message.hasPrefix("Failed to run yt-dlp"))
        #expect(downloader.progress == nil)
    }

    // MARK: - Cancellation

    @Test func cancelTerminatesTheSubprocessAndRemovesIntermediates() async throws {
        let sandbox = try Sandbox(script: """
        : > "$out.part"
        echo "[download]  10.0% of 1.00MiB"
        exec sleep 30
        """)
        let downloader = sandbox.makeDownloader()
        var reported: [Double?] = []

        let task = Task { @MainActor in
            await downloader.download(youtubeURL: Self.videoURL) { reported.append($0) }
        }
        try await waitUntil { downloader.progress == 0.1 }
        downloader.cancel()

        let outcome = await task.value
        #expect(outcome == .cancelled)
        #expect(reported.last == .some(nil))
        #expect(sandbox.cachedNames.isEmpty)
    }

    @Test func cancellingTheCallingTaskTerminatesTheSubprocess() async throws {
        let sandbox = try Sandbox(script: """
        echo "[download]  10.0% of 1.00MiB"
        exec sleep 30
        """)
        let downloader = sandbox.makeDownloader()

        let task = Task { @MainActor in await downloader.download(youtubeURL: Self.videoURL) }
        try await waitUntil { downloader.progress == 0.1 }
        task.cancel()

        let outcome = await task.value
        #expect(outcome == .cancelled)
        #expect(downloader.progress == nil)
    }

    /// `cancel` stops the running download only. A request queued behind it runs.
    @Test func cancelLeavesAQueuedDownloadToRun() async throws {
        let sandbox = try Sandbox(script: """
        case "$out" in
          *dQw4w9WgXcQ.mp4) echo "[download]  10.0% of 1.00MiB"; exec sleep 30 ;;
          *) : > "$out" ;;
        esac
        """)
        let downloader = sandbox.makeDownloader()

        let first = Task { @MainActor in await downloader.download(youtubeURL: Self.videoURL) }
        try await waitUntil { downloader.progress == 0.1 }
        let second = Task { @MainActor in await downloader.download(youtubeURL: "https://youtu.be/aaaaaaaaaaa") }
        await Task.yield()
        downloader.cancel()

        let firstOutcome = await first.value
        let secondOutcome = await second.value
        #expect(firstOutcome == .cancelled)
        #expect(secondOutcome == .success(sandbox.cache.appending(path: "aaaaaaaaaaa.mp4")))
    }

    // MARK: - Parsing

    @Test func progressFractionReadsYTDLPProgressLines() {
        #expect(YouTubeDownloader.progressFraction(in: "[download]  45.2% of ~12.34MiB at 1.2MiB/s") == 0.452)
        #expect(YouTubeDownloader.progressFraction(in: "[download] 100.0% of 12.34MiB") == 1)
        #expect(YouTubeDownloader.progressFraction(in: "[youtube] Extracting URL") == nil)
        #expect(YouTubeDownloader.progressFraction(in: "") == nil)
    }

    @Test func failureMessageTakesTheLastErrorLine() {
        let stderr = Data("ERROR: first\nWARNING: noise\nERROR: [youtube] abc: Private video\n".utf8)
        #expect(YouTubeDownloader.failureMessage(fromStandardError: stderr) == "[youtube] abc: Private video")
        #expect(YouTubeDownloader.failureMessage(fromStandardError: Data("no marker".utf8)) == "Download failed")
        #expect(YouTubeDownloader.failureMessage(fromStandardError: Data("ERROR:  \n".utf8)) == "Download failed")
        #expect(YouTubeDownloader.failureMessage(fromStandardError: Data()) == "Download failed")
    }
}

struct YTDLPInstallerTests {

    /// Known-answer tests: the hash gate is only as good as the digest it compares.
    @Test func sha256MatchesKnownAnswers() {
        #expect(
            YTDLPInstaller.sha256Hex(of: Data())
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        #expect(
            YTDLPInstaller.sha256Hex(of: Data("abc".utf8))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test func pinNamesAVersionAndAFullDigest() {
        #expect(!YTDLPInstaller.pinnedVersion.isEmpty)
        #expect(YTDLPInstaller.pinnedSHA256.count == 64)
    }
}
