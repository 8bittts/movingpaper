import AppKit
import Combine
import CryptoKit
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
    private var activeDownloadID: UUID?
    private var cancelledDownloadIDs = Set<UUID>()

    // MARK: - Cache Directory

    static var cacheDirectory: URL { AppPaths.youtubeCache }

    /// Returns the cached file URL if the video has already been downloaded.
    static func cachedFile(for videoID: String) -> URL? {
        let path = cacheDirectory.appendingPathComponent("\(videoID).mp4")
        return FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) ? path : nil
    }

    // MARK: - yt-dlp Binary

    /// Path to the yt-dlp binary. Checks Application Support first, then dev tools/.
    private static var ytdlpPath: String? {
        let installed = AppPaths.ytdlpBinary.path(percentEncoded: false)
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

    /// Pinned yt-dlp release. Bump both fields together — the SHA-256 is checked
    /// against the downloaded binary before it's installed and made executable.
    /// Refresh via `curl -fsSL https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest`
    /// when YouTube site changes break the current pinned version.
    nonisolated static let pinnedYTDLPVersion = "2026.03.17"
    nonisolated static let pinnedYTDLPSHA256 = "e80c47b3ce712acee51d5e3d4eace2d181b44d38f1942c3a32e3c7ff53cd9ed5"

    /// Download yt-dlp if not already installed. Returns path on success.
    /// Verifies the downloaded binary against the pinned SHA-256 before installing.
    static func ensureYTDLP() async -> String? {
        if let existing = ytdlpPath { return existing }

        let installURL = AppPaths.ytdlpBinary
        let dir = installURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let downloadURL = URL(string:
            "https://github.com/yt-dlp/yt-dlp/releases/download/\(pinnedYTDLPVersion)/yt-dlp_macos"
        )!
        do {
            let (data, response) = try await URLSession.shared.data(from: downloadURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            guard sha256Hex(of: data) == pinnedYTDLPSHA256 else {
                Log.youtube.error("yt-dlp SHA-256 mismatch for pinned version \(pinnedYTDLPVersion, privacy: .public); refusing to install")
                return nil
            }
            try data.write(to: installURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: installURL.path(percentEncoded: false)
            )
            return installURL.path(percentEncoded: false)
        } catch {
            return nil
        }
    }

    nonisolated static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

        if process != nil {
            cancel()
        }

        let downloadID = UUID()
        activeDownloadID = downloadID
        state = .downloading(progress: 0)

        let result = await runYTDLP(
            binary: ytdlp,
            downloadID: downloadID,
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

        guard activeDownloadID == downloadID else {
            try? FileManager.default.removeItem(atPath: partialPath)
            return nil
        }

        activeDownloadID = nil

        switch result {
        case .cancelled:
            state = .idle
            try? FileManager.default.removeItem(atPath: partialPath)
            return nil
        case .failed(let message):
            try? FileManager.default.removeItem(atPath: outputPath)
            try? FileManager.default.removeItem(atPath: partialPath)
            state = .failed(message)
            return nil
        case .succeeded:
            break
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
        if let activeDownloadID {
            cancelledDownloadIDs.insert(activeDownloadID)
        }

        let process = self.process
        self.process = nil
        activeDownloadID = nil
        state = .idle
        process?.terminate()
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

    private enum DownloadResult: Equatable {
        case succeeded
        case failed(String)
        case cancelled
    }

    private func runYTDLP(binary: String, downloadID: UUID, arguments: [String]) async -> DownloadResult {
        await withTaskCancellationHandler {
            await runYTDLPSubprocess(binary: binary, downloadID: downloadID, arguments: arguments)
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    private func runYTDLPSubprocess(binary: String, downloadID: UUID, arguments: [String]) async -> DownloadResult {
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
                            guard self?.activeDownloadID == downloadID else { return }
                            self?.state = .downloading(progress: percent / 100.0)
                        }
                    }
                }
            }

            proc.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                pipe.fileHandleForReading.closeFile()
                errPipe.fileHandleForReading.closeFile()

                Task { @MainActor [weak self] in
                    guard let self else {
                        continuation.resume(returning: .cancelled)
                        return
                    }

                    if self.process === proc {
                        self.process = nil
                    }

                    if self.cancelledDownloadIDs.remove(downloadID) != nil || self.activeDownloadID != downloadID {
                        continuation.resume(returning: .cancelled)
                        return
                    }

                    guard proc.terminationStatus == 0 else {
                        let errMsg = String(data: errData, encoding: .utf8) ?? ""
                        let userMessage = errMsg.contains("ERROR:")
                            ? errMsg.components(separatedBy: "ERROR:").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Download failed"
                            : "Download failed"
                        continuation.resume(returning: .failed(userMessage))
                        return
                    }

                    continuation.resume(returning: .succeeded)
                }
            }

            do {
                try proc.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                pipe.fileHandleForReading.closeFile()
                errPipe.fileHandleForReading.closeFile()
                if self.process === proc {
                    self.process = nil
                }
                continuation.resume(returning: .failed("Failed to run yt-dlp: \(error.localizedDescription)"))
            }
        }
    }
}
