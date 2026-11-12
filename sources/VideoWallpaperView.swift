import AVFoundation
import AppKit
import Combine

/// AppKit view hosting an `AVPlayerLayer` for hardware-accelerated, seamlessly
/// looping video wallpapers via `AVQueuePlayer` + `AVPlayerLooper`. Supports
/// `.mov`, `.mp4`, `.m4v` including HEVC with alpha.
@MainActor
final class VideoWallpaperView: NSView, WallpaperContentView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var statusObserver: AnyCancellable?
    private var looperObserver: AnyCancellable?
    private var endObserver: NSObjectProtocol?
    /// The asset load in flight. Internal so tests can await it.
    private(set) var loadTask: Task<Void, Never>?
    private var pendingResumeTime: CMTime?
    var onFailure: ((URL, String) -> Void)?

    var isMuted = true {
        didSet { player?.isMuted = isMuted }
    }

    /// Kept as state, not only forwarded to the player: a pause that arrives
    /// while the asset is still loading must hold once the player exists.
    var isPlaybackPaused = false {
        didSet {
            guard isPlaybackPaused != oldValue else { return }
            if isPlaybackPaused { player?.pause() } else { player?.play() }
        }
    }

    /// Current position of the live player, or nil before playback has advanced.
    var playbackTime: CMTime? {
        guard let time = player?.currentTime(), time.isValid, time.seconds > 0 else { return nil }
        return time
    }

    /// Whether the live player is advancing or about to. Internal for tests.
    var isPlaying: Bool {
        player.map { $0.timeControlStatus != .paused } ?? false
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
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

    func loadVideo(url: URL, resumeTime: CMTime? = nil) {
        tearDownPlayback()
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            onFailure?(url, "The wallpaper file is missing.")
            return
        }

        let asset = AVURLAsset(url: url)
        loadTask = Task { @MainActor [weak self] in
            do {
                // AVPlayerLooper needs duration loaded so loop points do not hitch,
                // and an unplayable file never fails the player on its own.
                let (_, isPlayable) = try await asset.load(.duration, .isPlayable)
                guard !Task.isCancelled else { return }
                guard isPlayable else {
                    self?.onFailure?(url, "The video couldn't be played.")
                    return
                }
                self?.install(asset: asset, url: url, resumeTime: resumeTime)
            } catch {
                guard !Task.isCancelled else { return }
                self?.onFailure?(url, error.localizedDescription)
            }
        }
    }

    private func install(asset: AVURLAsset, url: URL, resumeTime: CMTime?) {
        let queuePlayer = makePlayer()
        let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(asset: asset))

        attach(queuePlayer, url: url)
        looper = playerLooper
        looperObserver = playerLooper.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .failed {
                    self?.enableRewindFallback(asset: asset, url: url)
                }
            }

        start(at: resumeTime)
    }

    private func makePlayer(items: [AVPlayerItem] = []) -> AVQueuePlayer {
        let queuePlayer = AVQueuePlayer(items: items)
        queuePlayer.isMuted = isMuted
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        return queuePlayer
    }

    private func attach(_ queuePlayer: AVQueuePlayer, url: URL) {
        playerLayer.player = queuePlayer
        player = queuePlayer
        statusObserver = queuePlayer.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.seekToPendingResumeTime()
                case .failed:
                    let message = queuePlayer.error?.localizedDescription ?? "The video couldn't be played."
                    self?.onFailure?(url, message)
                default:
                    break
                }
            }
    }

    private func start(at resumeTime: CMTime?) {
        if let resumeTime, resumeTime.isValid, resumeTime.seconds > 0.1 {
            // Playback starts once the ready player has seeked there.
            pendingResumeTime = resumeTime
        } else {
            playIfNotPaused()
        }
    }

    private func seekToPendingResumeTime() {
        guard let resumeTime = pendingResumeTime else { return }
        pendingResumeTime = nil
        // Tight-but-not-zero tolerance avoids a decode hitch at resume.
        let slip = CMTime(seconds: 0.05, preferredTimescale: 600)
        player?.seek(to: resumeTime, toleranceBefore: slip, toleranceAfter: slip) { [weak self] finished in
            Task { @MainActor in
                guard finished else { return }
                self?.playIfNotPaused()
            }
        }
    }

    private func playIfNotPaused() {
        guard !isPlaybackPaused else { return }
        player?.play()
    }

    /// Apple: a looper whose status is `.failed` can no longer be used for
    /// playback. Replace it with a fresh player that holds one item, stays on it
    /// at the end (`actionAtItemEnd = .none`), and rewinds that item only.
    private func enableRewindFallback(asset: AVURLAsset, url: URL) {
        guard endObserver == nil else { return }
        Log.playback.error("AVPlayerLooper failed; falling back to rewind-at-end")
        let resumeTime = playbackTime
        looperObserver = nil
        looper?.disableLooping()
        looper = nil
        player?.pause()

        let item = AVPlayerItem(asset: asset)
        let fallback = makePlayer(items: [item])
        fallback.actionAtItemEnd = .none
        attach(fallback, url: url)
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.player?.seek(to: .zero)
                self.playIfNotPaused()
            }
        }
        start(at: resumeTime)
    }

    private func tearDownPlayback() {
        loadTask?.cancel()
        loadTask = nil
        pendingResumeTime = nil
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
    }

    override func removeFromSuperview() {
        tearDownPlayback()
        super.removeFromSuperview()
    }
}
