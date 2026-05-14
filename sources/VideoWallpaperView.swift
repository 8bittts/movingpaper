import AVFoundation
import Combine
import SwiftUI

/// Seamlessly looping video wallpaper using AVQueuePlayer + AVPlayerLooper.
/// Supports .mov, .mp4, .m4v formats including HEVC with alpha.
struct VideoWallpaperView: NSViewRepresentable {
    let url: URL
    var isMuted: Bool = true
    /// If set, the player seeks here once the first item is ready to play.
    var resumeTime: CMTime?

    func makeNSView(context: Context) -> VideoPlayerNSView {
        let view = VideoPlayerNSView()
        view.loadVideo(url: url, resumeTime: resumeTime)
        view.setMuted(isMuted)
        return view
    }

    func updateNSView(_ nsView: VideoPlayerNSView, context: Context) {
        if nsView.currentURL != url {
            nsView.loadVideo(url: url, resumeTime: resumeTime)
        }
        nsView.setMuted(isMuted)
    }
}

/// AppKit view hosting an AVPlayerLayer for hardware-accelerated video rendering.
final class VideoPlayerNSView: NSView {
    private(set) var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private(set) var currentURL: URL?
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

        currentURL = url

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
            statusObserver = item
                .publisher(for: \.status)
                .filter { $0 == .readyToPlay }
                .first()
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
