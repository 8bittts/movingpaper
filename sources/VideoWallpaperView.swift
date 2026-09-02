import AVFoundation
import AppKit
import Combine
import CoreMedia

/// AppKit view hosting an `AVPlayerLayer` for hardware-accelerated, seamlessly
/// looping video wallpapers via `AVQueuePlayer` + `AVPlayerLooper`. Supports
/// `.mov`, `.mp4`, `.m4v` including HEVC with alpha.
@MainActor
final class VideoPlayerNSView: NSView {
    private(set) var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var statusObserver: AnyCancellable?
    private var looperObserver: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    private var loadGeneration = 0
    private var desiredMuted = true
    private var didHandleReady = false
    var onFailure: ((URL, String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    /// Apple's recommended presentation: `AVPlayerLayer` as the view's backing
    /// layer, so frames are not composited through an extra CALayer (which can tear).
    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func setMuted(_ muted: Bool) {
        desiredMuted = muted
        player?.isMuted = muted
    }

    func loadVideo(url: URL, resumeTime: CMTime? = nil) {
        tearDownPlayback()
        loadGeneration += 1
        let token = loadGeneration

        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            onFailure?(url, "The wallpaper file is missing.")
            return
        }

        let asset = AVURLAsset(url: url)
        Task { @MainActor [weak self] in
            // AVPlayerLooper needs duration loaded so loop points do not hitch.
            _ = try? await asset.load(.duration)
            guard let self, token == self.loadGeneration else { return }
            self.install(asset: asset, url: url, resumeTime: resumeTime)
        }
    }

    private func install(asset: AVURLAsset, url: URL, resumeTime: CMTime?) {
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = desiredMuted
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        playerLayer.player = queuePlayer
        player = queuePlayer
        looper = playerLooper
        observePlayback(url: url, resumeTime: resumeTime)

        let shouldResume = resumeTime.map { $0.isValid && $0.seconds > 0.1 } ?? false
        if !shouldResume {
            queuePlayer.play()
        }
    }

    private func observePlayback(url: URL, resumeTime: CMTime?) {
        guard let queuePlayer = player else { return }

        statusObserver = queuePlayer.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.handleReady(resumeTime)
                case .failed:
                    let message = queuePlayer.error?.localizedDescription ?? "The video could not be played."
                    self.onFailure?(url, message)
                default:
                    break
                }
            }

        looperObserver = looper?.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .failed {
                    self?.enableRewindFallback()
                }
            }
    }

    private func handleReady(_ resumeTime: CMTime?) {
        guard !didHandleReady else { return }
        didHandleReady = true
        guard let queuePlayer = player,
              let resumeTime,
              resumeTime.isValid,
              resumeTime.seconds > 0.1
        else { return }
        // Tight-but-not-zero tolerance avoids a decode hitch at resume.
        let slip = CMTime(seconds: 0.05, preferredTimescale: 600)
        queuePlayer.seek(to: resumeTime, toleranceBefore: slip, toleranceAfter: slip) { [weak self] finished in
            Task { @MainActor in
                guard finished else { return }
                self?.player?.play()
            }
        }
    }

    private func enableRewindFallback() {
        guard endObserver == nil else { return }
        Log.playback.error("AVPlayerLooper failed; falling back to rewind-at-end")
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let ending = notification.object as? AVPlayerItem
            MainActor.assumeIsolated {
                guard let self, let ending, self.player?.currentItem === ending else { return }
                self.player?.seek(to: .zero)
                self.player?.play()
            }
        }
    }

    private func tearDownPlayback() {
        statusObserver = nil
        looperObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        looper = nil
        player = nil
        playerLayer.player = nil
        didHandleReady = false
    }

    override func removeFromSuperview() {
        tearDownPlayback()
        super.removeFromSuperview()
    }
}

extension VideoPlayerNSView: OcclusionPausable {
    func setOcclusionHidden(_ hidden: Bool) {
        if hidden { player?.pause() } else { player?.play() }
    }
}
