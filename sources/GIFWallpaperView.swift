import AppKit
import ImageIO

/// AppKit view that renders animated GIF frames into a `CALayer` via
/// `CGAnimateImageAtURLWithBlock`. The system handles frame timing from the
/// GIF's delay metadata automatically.
final class GIFAnimationNSView: NSView {
    private var imageLayer: CALayer?

    // The animation callback runs on a background thread, so the "is this
    // animation still current?" flag must be read/written under a lock. Each
    // `loadGIF`/`stopAnimation` bumps the generation; a callback whose captured
    // token no longer matches stops itself, preventing a stale second loop.
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

    override func layout() {
        super.layout()
        imageLayer?.frame = bounds
    }

    func loadGIF(url: URL) {
        imageLayer?.contents = nil
        let token = bumpGeneration()

        _ = CGAnimateImageAtURLWithBlock(
            url as CFURL,
            nil
        ) { [weak self] _, cgImage, stop in
            guard let self, self.isCurrent(token) else {
                stop.pointee = true
                return
            }
            if Thread.isMainThread {
                self.imageLayer?.contents = cgImage
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(token) else { return }
                    self.imageLayer?.contents = cgImage
                }
            }
        }
    }

    func stopAnimation() {
        _ = bumpGeneration()
        imageLayer?.contents = nil
    }

    override func removeFromSuperview() {
        stopAnimation()
        super.removeFromSuperview()
    }
}
