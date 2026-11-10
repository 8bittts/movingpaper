import Foundation
import os

/// Downloads YouTube videos into the local cache with the pinned yt-dlp binary.
@MainActor
final class YouTubeDownloader {

    /// Result of a single `download` call.
    enum DownloadOutcome: Equatable {
        case success(URL)
        case failure(String)
        /// Cancelled before it finished — nothing to apply or report.
        case cancelled
    }

    /// Receives the fraction complete while this call's download runs, then
    /// `nil` once it ends. Never called for a cache hit.
    typealias ProgressHandler = @MainActor (Double?) -> Void

    /// Fraction complete of the download in flight, or nil when none is running.
    private(set) var progress: Double? {
        didSet {
            guard progress != oldValue else { return }
            progressHandler?(progress)
        }
    }

    private var progressHandler: ProgressHandler?
    private var process: Process?
    /// Identifies the subprocess run in flight. `cancel` clears it, so a run
    /// that exits without matching it was cancelled.
    private var activeDownloadID: UUID?

    /// Serializes downloads so concurrent per-display requests each run to
    /// completion instead of terminating one another's subprocess.
    private let gate = AsyncSerialGate()
    private let cacheDirectory: URL
    private let resolveBinary: @Sendable () async -> String?

    init(
        cacheDirectory: URL = AppPaths.youtubeCache,
        resolveBinary: @escaping @Sendable () async -> String? = YTDLPInstaller.ensureYTDLP
    ) {
        self.cacheDirectory = cacheDirectory
        self.resolveBinary = resolveBinary
    }

    // MARK: - Download

    /// Download a YouTube video into the cache, or return the cached file.
    /// Serialized: only one download runs at a time (FIFO), so concurrent
    /// per-display requests all complete instead of clobbering each other.
    func download(
        youtubeURL: String,
        onProgress: @escaping ProgressHandler = { _ in }
    ) async -> DownloadOutcome {
        await gate.run {
            await self.performDownload(youtubeURL: youtubeURL, onProgress: onProgress)
        } ?? .cancelled
    }

    /// Cancel the download in flight, if any. Queued downloads still run.
    func cancel() {
        if let activeDownloadID {
            cancel(activeDownloadID)
        }
    }

    /// Scoped to one run, so a cancellation that lands late cannot terminate
    /// the download that started after it.
    private func cancel(_ downloadID: UUID) {
        guard downloadID == activeDownloadID else { return }
        activeDownloadID = nil
        progress = nil
        process?.terminate()
    }

    private func performDownload(
        youtubeURL: String,
        onProgress: @escaping ProgressHandler
    ) async -> DownloadOutcome {
        guard let videoID = YouTubeURLParser.videoID(from: youtubeURL) else {
            return .failure("Invalid YouTube URL")
        }

        let output = cacheDirectory.appending(path: "\(videoID).mp4")
        let outputPath = output.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: outputPath) {
            return .success(output)
        }

        guard let ytdlp = await resolveBinary() else {
            return .failure("Could not download yt-dlp. Check your internet connection.")
        }
        guard !Task.isCancelled else { return .cancelled }

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let downloadID = UUID()
        activeDownloadID = downloadID
        progressHandler = onProgress
        progress = 0

        let result = await runYTDLP(
            binary: ytdlp,
            downloadID: downloadID,
            arguments: [
                "-f", "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][height<=1080]/best[ext=mp4]/best",
                "--merge-output-format", "mp4",
                "--no-playlist",
                "--newline",
                "--progress",
                // Bound network stalls so a hung connection self-terminates instead
                // of wedging the serial download gate indefinitely.
                "--socket-timeout", "30",
                "--retries", "3",
                "-o", outputPath,
                youtubeURL,
            ]
        )

        activeDownloadID = nil
        progress = nil
        progressHandler = nil

        switch result {
        case .succeeded:
            guard FileManager.default.fileExists(atPath: outputPath) else {
                return .failure("Download completed but file not found")
            }
            return .success(output)
        case .failed(let message):
            removeIntermediates(videoID: videoID)
            return .failure(message)
        case .cancelled:
            removeIntermediates(videoID: videoID)
            return .cancelled
        }
    }

    /// Remove every cache file yt-dlp may have written for this video — the merged
    /// output, its `.part`, the per-format `<id>.f*.mp4/.m4a` streams (and their
    /// `.part`s), and the `.ytdl` state file — so a cancelled or failed run doesn't
    /// orphan intermediates. Scoped to names beginning with "<videoID>." so it never
    /// touches another video's cached file.
    private func removeIntermediates(videoID: String) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        let prefix = "\(videoID)."
        for entry in entries where entry.lastPathComponent.hasPrefix(prefix) {
            try? fileManager.removeItem(at: entry)
        }
    }

    // MARK: - Process Runner

    private enum RunResult {
        case succeeded
        case failed(String)
        case cancelled
    }

    /// The inherited environment with the common ffmpeg locations on `PATH`.
    private static var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let inherited = (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
        var seen = Set<String>()
        environment["PATH"] = (["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] + inherited)
            .filter { seen.insert($0).inserted }
            .joined(separator: ":")
        return environment
    }

    /// Compiled once, not per stdout chunk. Matches yt-dlp progress like "45.2%".
    private nonisolated static let progressRegex = try! NSRegularExpression(pattern: #"(\d+\.\d+)%"#)

    /// The fraction in a yt-dlp progress line like "[download]  45.2% of ~12.34MiB".
    nonisolated static func progressFraction(in output: String) -> Double? {
        let range = NSRange(output.startIndex..., in: output)
        guard let match = progressRegex.firstMatch(in: output, range: range),
              let percentRange = Range(match.range(at: 1), in: output),
              let percent = Double(output[percentRange])
        else { return nil }
        return percent / 100
    }

    /// The text after yt-dlp's last "ERROR:" marker, or a generic message.
    nonisolated static func failureMessage(fromStandardError data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self)
        guard let marker = text.range(of: "ERROR:", options: .backwards) else {
            return "Download failed"
        }
        let message = text[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Download failed" : message
    }

    private func runYTDLP(binary: String, downloadID: UUID, arguments: [String]) async -> RunResult {
        await withTaskCancellationHandler {
            await runYTDLPSubprocess(binary: binary, downloadID: downloadID, arguments: arguments)
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(downloadID) }
        }
    }

    private func runYTDLPSubprocess(binary: String, downloadID: UUID, arguments: [String]) async -> RunResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: binary)
            process.arguments = arguments
            process.environment = Self.processEnvironment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            // Drain stderr continuously; otherwise a chatty yt-dlp run can fill the
            // pipe buffer and block the child while we wait for it to exit.
            let errorOutput = OSAllocatedUnfairLock(initialState: Data())
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    errorOutput.withLock { $0.append(chunk) }
                }
            }

            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty,
                      let fraction = Self.progressFraction(in: String(decoding: chunk, as: UTF8.self))
                else { return }
                Task { @MainActor in
                    guard let self, self.activeDownloadID == downloadID else { return }
                    self.progress = fraction
                }
            }

            process.terminationHandler = { [weak self] process in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                let errorData = errorOutput.withLock { $0 } + errorPipe.fileHandleForReading.readDataToEndOfFile()
                try? outputPipe.fileHandleForReading.close()
                try? errorPipe.fileHandleForReading.close()
                let status = process.terminationStatus

                Task { @MainActor in
                    guard let self else {
                        continuation.resume(returning: .cancelled)
                        return
                    }
                    self.process = nil
                    if self.activeDownloadID != downloadID {
                        continuation.resume(returning: .cancelled)
                    } else if status == 0 {
                        continuation.resume(returning: .succeeded)
                    } else {
                        continuation.resume(returning: .failed(Self.failureMessage(fromStandardError: errorData)))
                    }
                }
            }

            do {
                try process.run()
                self.process = process
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: .failed("Failed to run yt-dlp: \(error.localizedDescription)"))
            }
        }
    }
}
