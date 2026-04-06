import AVFoundation
import SwiftUI

/// Seamlessly looping video wallpaper using AVQueuePlayer + AVPlayerLooper.
/// Supports .mov, .mp4, .m4v formats including HEVC with alpha.
struct VideoWallpaperView: NSViewRepresentable {
    let url: URL
    var isMuted: Bool = true

    func makeNSView(context: Context) -> VideoPlayerNSView {
        let view = VideoPlayerNSView()
        view.loadVideo(url: url)
        view.setMuted(isMuted)
        return view
    }

    func updateNSView(_ nsView: VideoPlayerNSView, context: Context) {
        if nsView.currentURL != url {
            nsView.loadVideo(url: url)
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

    func loadVideo(url: URL) {
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

        queuePlayer.play()
    }

    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }

    override func removeFromSuperview() {
        player?.pause()
        looper = nil
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        super.removeFromSuperview()
    }
}
