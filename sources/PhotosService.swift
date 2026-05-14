@preconcurrency import AVFoundation
@preconcurrency import Photos

/// Fetches random videos from the Photos library for shuffle mode.
@MainActor
final class PhotosService: @unchecked Sendable {

    nonisolated func requestAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { return true }
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return newStatus == .authorized || newStatus == .limited
    }

    /// Fetch a random video URL from the entire Photos library.
    /// Tries up to 3 random assets if export fails (iCloud-only, corrupted, etc.).
    nonisolated func randomVideoURL() async -> URL? {
        guard await requestAccess() else { return nil }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        let allVideos = PHAsset.fetchAssets(with: options)
        guard allVideos.count > 0 else { return nil }

        for _ in 0..<3 {
            let index = Int.random(in: 0..<allVideos.count)
            if let url = await exportVideo(asset: allVideos.object(at: index)) {
                return url
            }
        }
        return nil
    }

    nonisolated private func exportVideo(asset: PHAsset) async -> URL? {
        let cacheDir = AppPaths.photosShuffleCache
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let destURL = cacheDir.appendingPathComponent("\(asset.localIdentifier.replacingOccurrences(of: "/", with: "-")).mp4")

        if FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
            return destURL
        }

        // Request export session with a 15s timeout to avoid hanging on iCloud assets
        nonisolated(unsafe) var exportSession: AVAssetExportSession?
        let gotSession = await withTimeout(seconds: 15) { [self] in
            exportSession = await self.requestExportSession(for: asset)
            return exportSession != nil
        } ?? false

        guard gotSession, let session = exportSession else { return nil }

        // Export with a 30s timeout
        nonisolated(unsafe) let sendableSession = session
        let exported = await withTimeout(seconds: 30) { [self] in
            await self.export(session: sendableSession, to: destURL)
        } ?? false

        if exported, FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
            return destURL
        }

        // Clean up partial file on failure
        try? FileManager.default.removeItem(at: destURL)
        return nil
    }

    nonisolated private func requestExportSession(for asset: PHAsset) async -> AVAssetExportSession? {
        nonisolated(unsafe) var requestID: PHImageRequestID = PHInvalidImageRequestID
        nonisolated(unsafe) var exportSession: AVAssetExportSession?

        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                let reqOptions = PHVideoRequestOptions()
                reqOptions.isNetworkAccessAllowed = true
                reqOptions.deliveryMode = .highQualityFormat

                requestID = PHImageManager.default().requestExportSession(
                    forVideo: asset,
                    options: reqOptions,
                    exportPreset: AVAssetExportPresetHighestQuality
                ) { session, _ in
                    exportSession = session
                    continuation.resume()
                }
            }
        }, onCancel: {
            if requestID != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        })

        return exportSession
    }

    nonisolated private func export(session: AVAssetExportSession, to destURL: URL) async -> Bool {
        nonisolated(unsafe) let session = session
        return await withTaskCancellationHandler(operation: {
            do {
                try await session.export(to: destURL, as: .mp4)
                return true
            } catch {
                return false
            }
        }, onCancel: {
            session.cancelExport()
        })
    }
}

/// Run an async operation with a timeout. Returns nil if the timeout expires.
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
