import AppKit
import ImageIO

/// AppKit view that renders animated GIF frames into a `CALayer` via
/// `CGAnimateImageAtURLWithBlock`. The system handles frame timing from the
/// GIF's delay metadata automatically.
@MainActor
final class GIFWallpaperView: NSView, WallpaperContentView {
    private var imageLayer: CALayer?
    /// The GIF currently loaded, so a resume can restart it.
    private(set) var currentURL: URL?
    var onFailure: ((URL, String) -> Void)?

    /// Identifies the live animation. ImageIO has no cancel call, so a frame
    /// callback that carries a stale value stops its own loop. Internal for tests.
    private(set) var animationGeneration = 0

    var isPlaybackPaused = false {
        didSet {
            guard isPlaybackPaused != oldValue else { return }
            if isPlaybackPaused {
                // Keep the last frame up so a pause does not flash the desktop
                // through an empty layer.
                animationGeneration += 1
            } else if let currentURL {
                // CGAnimateImageAtURLWithBlock has no resume-at-frame API, so a revealed
                // GIF restarts from the first frame — the last frame stays visible until
                // the first new callback arrives.
                loadGIF(url: currentURL)
            }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let layer = CALayer()
        layer.contentsGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.layer?.addSublayer(layer)
        self.imageLayer = layer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        imageLayer?.contentsScale = scale
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer?.frame = bounds
        CATransaction.commit()
    }

    func loadGIF(url: URL) {
        currentURL = url
        animationGeneration += 1
        guard !isPlaybackPaused else {
            displayFirstFrame(of: url)
            return
        }
        let generation = animationGeneration
        // Wallpaper GIFs must loop even when the file's Netscape count is 1.
        let options: NSDictionary = [kCGImageAnimationLoopCount: Double.infinity]
        // ImageIO runs the block on the main queue.
        let status = CGAnimateImageAtURLWithBlock(
            url as CFURL,
            options
        ) { [weak self] _, cgImage, stop in
            guard let self, generation == self.animationGeneration else {
                stop.pointee = true
                return
            }
            self.displayFrame(cgImage)
        }
        if status != noErr {
            currentURL = nil
            onFailure?(url, Self.playbackMessage(status: status))
        }
    }

    /// A GIF loaded while paused shows its first frame instead of an empty panel.
    private func displayFirstFrame(of url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            currentURL = nil
            onFailure?(url, Self.playbackMessage(status: CGImageAnimationStatus.parameterError.rawValue))
            return
        }
        displayFrame(image)
    }

    /// Present a frame without CALayer's implicit fade (which looks like tearing).
    func displayFrame(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer?.contents = image
        CATransaction.commit()
    }

    var hasVisibleContents: Bool { imageLayer?.contents != nil }

    override func removeFromSuperview() {
        animationGeneration += 1
        super.removeFromSuperview()
    }

    static func playbackMessage(status: OSStatus) -> String {
        switch status {
        case CGImageAnimationStatus.parameterError.rawValue:
            return "The GIF couldn't be opened."
        case CGImageAnimationStatus.corruptInputImage.rawValue:
            return "The GIF file is unreadable."
        case CGImageAnimationStatus.unsupportedFormat.rawValue:
            return "That image format can't be animated."
        case CGImageAnimationStatus.incompleteInputImage.rawValue:
            return "The GIF file is incomplete."
        case CGImageAnimationStatus.allocationFailure.rawValue:
            return "There isn't enough memory to play that GIF."
        default:
            return "The GIF couldn't be played."
        }
    }
}
