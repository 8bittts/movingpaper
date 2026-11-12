import AVFoundation
import Photos
import os

/// Why a Photos shuffle produced no video, with the alert copy that explains it.
enum PhotosShuffleFailure: Equatable {
    case accessDenied
    case noVideos
    case exportFailed

    var alertTitle: String {
        switch self {
        case .accessDenied: "Photos Access Needed"
        case .noVideos: "No Videos Found"
        case .exportFailed: "Couldn't Shuffle"
        }
    }

    var alertMessage: String {
        switch self {
        case .accessDenied:
            "Allow Photos access in System Settings to shuffle videos as wallpaper."
        case .noVideos:
            "Add a video to your Photos library, then try Shuffle from Photos again."
        case .exportFailed:
            "MovingPaper couldn't export a video from Photos. Try again, or choose a video with Choose from Photos."
        }
    }
}

enum PhotosShuffleOutcome: Equatable {
    case video(URL)
    case failed(PhotosShuffleFailure)
}

/// Fetches random videos from the Photos library for shuffle mode.
/// Stateless, so callable from any isolation.
enum PhotosService {

    private static func requestAccess() async -> Bool {
        // `.readWrite` is the minimal access level that can read the library —
        // PHAccessLevel offers only `.addOnly` and `.readWrite`, no read-only level.
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { return true }
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return newStatus == .authorized || newStatus == .limited
    }

    /// Fetch a random video from the entire Photos library.
    /// Tries up to 3 random assets if export fails (iCloud-only, corrupted, etc.).
    static func shuffle() async -> PhotosShuffleOutcome {
        guard await requestAccess() else {
            Log.photos.notice("Photos access denied; cannot shuffle")
            return .failed(.accessDenied)
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        let allVideos = PHAsset.fetchAssets(with: options)
        guard allVideos.count > 0 else {
            Log.photos.notice("No videos found in Photos library")
            return .failed(.noVideos)
        }

        for attempt in 0..<3 {
            guard !Task.isCancelled else { return .failed(.exportFailed) }
            let index = Int.random(in: 0..<allVideos.count)
            if let url = await exportVideo(asset: allVideos.object(at: index)) {
                return .video(url)
            }
            Log.photos.notice("Shuffle export attempt \(attempt + 1, privacy: .public)/3 failed")
        }
        return .failed(.exportFailed)
    }

    private static func exportVideo(asset: PHAsset) async -> URL? {
        let cacheDir = AppPaths.photosShuffleCache
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let destURL = cacheDir.appendingPathComponent("\(asset.localIdentifier.replacingOccurrences(of: "/", with: "-")).mp4")

        // Only a finished export is ever moved to `destURL`, so an existing file
        // there is complete.
        if FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
            return destURL
        }

        // Request export session with a 15s timeout to avoid hanging on iCloud assets
        nonisolated(unsafe) var exportSession: AVAssetExportSession?
        let gotSession = await withTimeout(seconds: 15) {
            exportSession = await requestExportSession(for: asset)
            return exportSession != nil
        } ?? false

        guard gotSession, let session = exportSession else { return nil }

        // Export to a file of this run's own, then move it into place. Two
        // shuffles can pick the same asset; a shared path would let one read the
        // other's half-written file, or delete it on failure while it plays.
        let partialURL = cacheDir.appendingPathComponent("\(UUID().uuidString).partial.mp4")
        defer { try? FileManager.default.removeItem(at: partialURL) }

        // Export with a 30s timeout
        nonisolated(unsafe) let sendableSession = session
        let exported = await withTimeout(seconds: 30) {
            await export(session: sendableSession, to: partialURL)
        } ?? false
        guard exported else { return nil }

        do {
            try FileManager.default.moveItem(at: partialURL, to: destURL)
        } catch where FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
            // Another shuffle finished the same asset first; its file is complete.
        } catch {
            Log.photos.error("Couldn't move the shuffle export into the cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return destURL
    }

    /// An export session crossing from PhotoKit's callback queue.
    private struct SessionBox: @unchecked Sendable {
        let session: AVAssetExportSession?
    }

    /// Shared between the request, PhotoKit's result handler and the
    /// cancellation handler, which run concurrently.
    private struct ExportRequestState {
        var requestID = PHInvalidImageRequestID
        var cancelled = false
        var continuation: CheckedContinuation<SessionBox, Never>?

        /// Hand out the continuation at most once, so it is resumed exactly once.
        mutating func takeContinuation() -> CheckedContinuation<SessionBox, Never>? {
            defer { continuation = nil }
            return continuation
        }
    }

    /// Cancellation resumes the wait itself. PhotoKit documents a result-handler
    /// call after cancellation only for image requests, and a continuation that
    /// is never resumed suspends the shuffle forever.
    private static func requestExportSession(for asset: PHAsset) async -> AVAssetExportSession? {
        let state = OSAllocatedUnfairLock(initialState: ExportRequestState())

        let box = await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<SessionBox, Never>) in
                let alreadyCancelled = state.withLock { state in
                    if state.cancelled { return true }
                    state.continuation = continuation
                    return false
                }
                if alreadyCancelled {
                    continuation.resume(returning: SessionBox(session: nil))
                    return
                }

                let reqOptions = PHVideoRequestOptions()
                reqOptions.isNetworkAccessAllowed = true
                reqOptions.deliveryMode = .highQualityFormat

                let id = PHImageManager.default().requestExportSession(
                    forVideo: asset,
                    options: reqOptions,
                    exportPreset: AVAssetExportPresetHighestQuality
                ) { session, info in
                    if session == nil, let error = info?[PHImageErrorKey] as? Error {
                        Log.photos.error("Photos export session failed: \(error.localizedDescription, privacy: .public)")
                    }
                    state.withLock { $0.takeContinuation() }?.resume(returning: SessionBox(session: session))
                }
                // A cancel that arrived before the ID existed could not cancel the request.
                let cancelNow = state.withLock { state in
                    state.requestID = id
                    return state.cancelled
                }
                if cancelNow {
                    PHImageManager.default().cancelImageRequest(id)
                }
            }
        }, onCancel: {
            let (id, continuation) = state.withLock { state in
                state.cancelled = true
                return (state.requestID, state.takeContinuation())
            }
            if id != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(id)
            }
            continuation?.resume(returning: SessionBox(session: nil))
        })

        return box.session
    }

    /// Cancelling the calling task cancels the export, so the timeout around
    /// this call needs no handler of its own.
    private static func export(session: AVAssetExportSession, to destURL: URL) async -> Bool {
        do {
            try await session.export(to: destURL, as: .mp4)
            return true
        } catch {
            if !Task.isCancelled {
                Log.photos.error("Photos export failed: \(error.localizedDescription, privacy: .public)")
            }
            return false
        }
    }
}

/// Run an async operation with a timeout. Returns nil if the timeout expires.
///
/// A task group waits for every child before it returns, even canceled ones, so
/// the timeout bounds the wait only because `operation` ends promptly on
/// cancellation: `requestExportSession` resumes itself and `export(to:as:)`
/// throws when canceled.
private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
