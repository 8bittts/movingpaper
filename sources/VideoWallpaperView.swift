import AVFoundation
import AppKit
import Combine
import CoreMedia

/// AppKit view hosting an `AVPlayerLayer` for hardware-accelerated, seamlessly
/// looping video wallpapers via `AVQueuePlayer` + `AVPlayerLooper`. Supports
/// `.mov`, `.mp4`, `.m4v` including HEVC with alpha.
final class VideoPlayerNSView: NSView {
    private(set) var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var statusObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    func loadVideo(url: URL, resumeTime: CMTime? = nil) {
        statusObserver = nil
        player?.pause()
        looper = nil
        player = nil
        playerLayer?.removeFromSuperlayer()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer()
        let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        let layer = AVPlayerLayer(player: queuePlayer)
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.layer?.addSublayer(layer)

        self.player = queuePlayer
        self.looper = playerLooper
        self.playerLayer = layer

        if let resumeTime, resumeTime.isValid, resumeTime.seconds > 0.1 {
            // Observe the queue player itself (not the looper's template item, whose
            // status can stay `.unknown` since it is never enqueued for playback),
            // and deliver on the main thread before touching main-actor state.
            statusObserver = queuePlayer
                .publisher(for: \.status)
                .filter { $0 == .readyToPlay }
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    queuePlayer.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    self?.statusObserver = nil
                }
        }

        queuePlayer.play()
    }

    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }

    override func removeFromSuperview() {
        statusObserver = nil
        player?.pause()
        looper = nil
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        super.removeFromSuperview()
    }
}

extension VideoPlayerNSView: OcclusionPausable {
    func setOcclusionHidden(_ hidden: Bool) {
        if hidden { player?.pause() } else { player?.play() }
    }
}
