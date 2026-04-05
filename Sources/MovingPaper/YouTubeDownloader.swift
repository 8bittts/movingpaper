import AppKit
import Combine
import Foundation

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

/// Downloads YouTube videos to local cache using bundled yt-dlp binary.
@MainActor
final class YouTubeDownloader: ObservableObject {

    enum State: Equatable {
        case idle
        case downloading(progress: Double)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var process: Process?

    // MARK: - Cache Directory

    static var cacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MovingPaper/YouTube", isDirectory: true)
    }

    /// Returns the cached file URL if the video has already been downloaded.
    static func cachedFile(for videoID: String) -> URL? {
        let path = cacheDirectory.appendingPathComponent("\(videoID).mp4")
        return FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) ? path : nil
    }

    // MARK: - yt-dlp Binary

    /// yt-dlp binary location in Application Support (downloaded on first use).
    private static var ytdlpInstallPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MovingPaper/yt-dlp")
    }

    /// Path to the yt-dlp binary. Checks Application Support first, then dev tools/.
    private static var ytdlpPath: String? {
        let installed = ytdlpInstallPath.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: installed) {
            return installed
        }
        // Dev build: tools directory relative to working directory
        let devPath = "tools/yt-dlp/yt-dlp"
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }
        return nil
    }

    /// Download yt-dlp if not already installed. Returns path on success.
    static func ensureYTDLP() async -> String? {
        if let existing = ytdlpPath { return existing }

        let installURL = ytdlpInstallPath
        let dir = installURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Download from GitHub releases
        let downloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
        do {
            let (data, response) = try await URLSession.shared.data(from: downloadURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            try data.write(to: installURL)
            // Make executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installURL.path(percentEncoded: false))
            return installURL.path(percentEncoded: false)
        } catch {
            return nil
        }
    }

    // MARK: - Download

    /// Download a YouTube video and return the local file URL.
    /// Returns nil on failure (state will be .failed with a message).
    func download(youtubeURL: String) async -> URL? {
        guard let videoID = YouTubeURLParser.videoID(from: youtubeURL) else {
            state = .failed("Invalid YouTube URL")
            return nil
        }

        // Check cache first
        if let cached = Self.cachedFile(for: videoID) {
            state = .idle
            return cached
        }

        let ytdlp: String
        if let existing = Self.ytdlpPath {
            ytdlp = existing
        } else if let downloaded = await Self.ensureYTDLP() {
            ytdlp = downloaded
        } else {
            state = .failed("Could not download yt-dlp. Check your internet connection.")
            return nil
        }

        // Ensure cache directory exists
        let cacheDir = Self.cacheDirectory
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let outputPath = cacheDir.appendingPathComponent("\(videoID).mp4").path(percentEncoded: false)
        let partialPath = cacheDir.appendingPathComponent("\(videoID).part").path(percentEncoded: false)

        state = .downloading(progress: 0)

        let result = await runYTDLP(
            binary: ytdlp,
            arguments: [
                "-f", "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][height<=1080]/best[ext=mp4]/best",
                "--merge-output-format", "mp4",
                "--no-playlist",
                "--newline",
                "--progress",
                "-o", outputPath,
                youtubeURL,
            ]
        )

        // Clean up partial file on failure
        if !result {
            try? FileManager.default.removeItem(atPath: outputPath)
            try? FileManager.default.removeItem(atPath: partialPath)
            if case .downloading = state {
                state = .failed("Download failed")
            }
            return nil
        }

        guard FileManager.default.fileExists(atPath: outputPath) else {
            state = .failed("Download completed but file not found")
            return nil
        }

        state = .idle
        return URL(filePath: outputPath)
    }

    /// Cancel an in-progress download.
    func cancel() {
        process?.terminate()
        process = nil
        state = .idle
    }

    // MARK: - Process Runner

    /// Build PATH that includes common ffmpeg locations.
    private static var processEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        let combined = (extraPaths + currentPath.split(separator: ":").map(String.init))
            .uniqued()
            .joined(separator: ":")
        env["PATH"] = combined
        return env
    }

    private func runYTDLP(binary: String, arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let proc = Process()
            proc.executableURL = URL(filePath: binary)
            proc.arguments = arguments
            proc.environment = Self.processEnvironment

            let pipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = errPipe

            self.process = proc

            // Read output on background thread, dispatch progress to MainActor
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }

                // Parse yt-dlp progress lines like "[download]  45.2% of ~12.34MiB"
                if let range = line.range(of: #"\d+\.\d+%"#, options: .regularExpression) {
                    let percentStr = line[range].dropLast() // remove %
                    if let percent = Double(percentStr) {
                        Task { @MainActor [weak self] in
                            self?.state = .downloading(progress: percent / 100.0)
                        }
                    }
                }
            }

            proc.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                let success = proc.terminationStatus == 0
                if !success {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? ""
                    Task { @MainActor [weak self] in
                        let userMsg = errMsg.contains("ERROR:")
                            ? errMsg.components(separatedBy: "ERROR:").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Download failed"
                            : "Download failed"
                        self?.state = .failed(userMsg)
                        self?.process = nil
                    }
                } else {
                    Task { @MainActor [weak self] in
                        self?.process = nil
                    }
                }
                continuation.resume(returning: success)
            }

            do {
                try proc.run()
            } catch {
                Task { @MainActor [weak self] in
                    self?.state = .failed("Failed to run yt-dlp: \(error.localizedDescription)")
                    self?.process = nil
                }
                continuation.resume(returning: false)
            }
        }
    }
}
