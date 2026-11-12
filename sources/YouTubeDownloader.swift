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
    /// that exits without matching it was canceled.
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
            return .failure("That doesn't look like a YouTube URL.")
        }

        let output = cacheDirectory.appending(path: "\(videoID).mp4")
        let outputPath = output.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: outputPath) {
            return .success(output)
        }

        guard let ytdlp = await resolveBinary() else {
            return .failure("MovingPaper couldn't install its YouTube downloader. Check your internet connection.")
        }
        guard !Task.isCancelled else { return .cancelled }

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        excludeCacheFromBackup()

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
                return .failure("The download finished, but the video file is missing.")
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

    /// Apple: exclude files the app can download again, such as videos kept for
    /// offline viewing, from backups. Every file here can be fetched again from
    /// its saved YouTube URL; the Photos caches cannot, so they stay backed up.
    private func excludeCacheFromBackup() {
        var directory = cacheDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try directory.setResourceValues(values)
        } catch {
            Log.youtube.error("Couldn't exclude the YouTube cache from backup: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Remove every cache file yt-dlp may have written for this video — the merged
    /// output, its `.part`, the per-format `<id>.f*.mp4/.m4a` streams (and their
    /// `.part`s), and the `.ytdl` state file — so a canceled or failed run doesn't
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

    /// What one subprocess run left behind, gathered off the main actor.
    private struct ProcessExit {
        var status: Int32 = 0
        var errorOutput = Data()
        /// Set when the process never launched.
        var launchError: String?
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
        let fallback = "The download failed."
        guard let marker = text.range(of: "ERROR:", options: .backwards) else { return fallback }
        let message = text[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? fallback : message
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

            // A run is over when the process has exited AND stderr has reached its
            // end. Waiting for both, without blocking a thread on either, means the
            // closing "ERROR:" line cannot be lost to a read still in flight when
            // the process exits.
            let finished = DispatchGroup()
            let exit = OSAllocatedUnfairLock(initialState: ProcessExit())
            finished.enter() // the process exits
            finished.enter() // stderr ends

            process.terminationHandler = { process in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                exit.withLock { $0.status = process.terminationStatus }
                finished.leave()
            }

            finished.notify(queue: .main) { [weak self] in
                // Holding the pipe here keeps its read handler alive until the end.
                _ = errorPipe
                let exit = exit.withLock { $0 }
                MainActor.assumeIsolated {
                    guard let self else {
                        continuation.resume(returning: .cancelled)
                        return
                    }
                    self.process = nil
                    if let launchError = exit.launchError {
                        continuation.resume(returning: .failed("The YouTube downloader couldn't start. \(launchError)"))
                    } else if self.activeDownloadID != downloadID {
                        continuation.resume(returning: .cancelled)
                    } else if exit.status == 0 {
                        continuation.resume(returning: .succeeded)
                    } else {
                        continuation.resume(returning: .failed(Self.failureMessage(fromStandardError: exit.errorOutput)))
                    }
                }
            }

            do {
                try process.run()
                self.process = process
            } catch {
                // Nothing launched, so neither event will arrive. No read handler is
                // installed yet, so both are settled here, exactly once.
                process.terminationHandler = nil
                exit.withLock { $0.launchError = error.localizedDescription }
                finished.leave()
                finished.leave()
                return
            }

            // Installed after launch: output written before this point waits in the
            // pipe. Draining stderr as it arrives also keeps a chatty run from
            // filling the pipe and blocking the child. An empty read is its end.
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    finished.leave()
                } else {
                    exit.withLock { $0.errorOutput.append(chunk) }
                }
            }

            // The termination handler also clears this one, but it can run before
            // this line installs it; an empty read is the end, so clear it there too.
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                guard let fraction = Self.progressFraction(in: String(decoding: chunk, as: UTF8.self))
                else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.activeDownloadID == downloadID else { return }
                    self.progress = fraction
                }
            }
        }
    }
}
