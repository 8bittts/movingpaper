import AppKit
import ImageIO

/// AppKit view that renders animated GIF frames into a `CALayer` via
/// `CGAnimateImageAtURLWithBlock`. The system handles frame timing from the
/// GIF's delay metadata automatically.
@MainActor
final class GIFAnimationNSView: NSView {
    private var imageLayer: CALayer?
    /// The GIF currently loaded, so occlusion resume can restart it.
    private(set) var currentURL: URL?
    var onFailure: ((URL, String) -> Void)?

    // The animation callback is documented to run on the main queue, but we
    // still treat generation as cross-thread so a late callback cannot restart
    // a stopped loop.
    private let stateLock = NSLock()
    nonisolated(unsafe) private var generation = 0

    private nonisolated func bumpGeneration() -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        generation += 1
        return generation
    }

    private nonisolated func isCurrent(_ token: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return token == generation
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
        let token = bumpGeneration()
        // Wallpaper GIFs must loop even when the file's Netscape count is 1.
        let options: NSDictionary = [kCGImageAnimationLoopCount: Double.infinity]
        let status = CGAnimateImageAtURLWithBlock(
            url as CFURL,
            options
        ) { [weak self] _, cgImage, stop in
            guard let self, self.isCurrent(token) else {
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

    /// Present a frame without CALayer's implicit fade (which looks like tearing).
    /// ImageIO calls the animation block on the main queue.
    func displayFrame(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer?.contents = image
        CATransaction.commit()
    }

    var hasVisibleContents: Bool { imageLayer?.contents != nil }

    func stopAnimation() {
        _ = bumpGeneration()
        // Keep the last frame up so occlusion/power pause does not flash the
        // desktop through an empty layer.
    }

    override func removeFromSuperview() {
        stopAnimation()
        super.removeFromSuperview()
    }

    static func playbackMessage(status: OSStatus) -> String {
        switch status {
        case CGImageAnimationStatus.parameterError.rawValue:
            return "The GIF could not be opened."
        case CGImageAnimationStatus.corruptInputImage.rawValue:
            return "The GIF file is unreadable."
        case CGImageAnimationStatus.unsupportedFormat.rawValue:
            return "That image format cannot be animated."
        case CGImageAnimationStatus.incompleteInputImage.rawValue:
            return "The GIF file is incomplete."
        case CGImageAnimationStatus.allocationFailure.rawValue:
            return "Not enough memory to play that GIF."
        default:
            return "The GIF could not be played."
        }
    }
}

extension GIFAnimationNSView: OcclusionPausable {
    func setOcclusionHidden(_ hidden: Bool) {
        if hidden {
            stopAnimation()
        } else if let currentURL {
            // CGAnimateImageAtURLWithBlock has no resume-at-frame API, so a revealed
            // GIF restarts from the first frame — the last frame stays visible until
            // the first new callback arrives.
            loadGIF(url: currentURL)
        }
    }
}
