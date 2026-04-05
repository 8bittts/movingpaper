import AVFoundation
import SwiftUI

/// Seamlessly looping video wallpaper using AVQueuePlayer + AVPlayerLooper.
/// Supports .mov, .mp4, .m4v formats including HEVC with alpha.
struct VideoWallpaperView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> VideoPlayerNSView {
        let view = VideoPlayerNSView()
        view.loadVideo(url: url)
        return view
    }

    func updateNSView(_ nsView: VideoPlayerNSView, context: Context) {
        if nsView.currentURL != url {
            nsView.loadVideo(url: url)
        }
    }
}

/// AppKit view hosting an AVPlayerLayer for hardware-accelerated video rendering.
final class VideoPlayerNSView: NSView {
    private var player: AVQueuePlayer?
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
        // Tear down previous playback
        player?.pause()
        looper = nil
        player = nil
        playerLayer?.removeFromSuperlayer()

        currentURL = url

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer()

        // AVPlayerLooper handles seamless gapless looping
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

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.play()
    }

    // ARC handles AVPlayer/AVPlayerLooper cleanup on dealloc
}
