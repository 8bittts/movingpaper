import AppKit
import ImageIO
import SwiftUI

/// Animated GIF wallpaper using CGAnimateImageAtURLWithBlock (macOS 10.15+).
/// The system handles frame timing from the GIF's delay metadata automatically.
struct GIFWallpaperView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> GIFAnimationNSView {
        let view = GIFAnimationNSView()
        view.loadGIF(url: url)
        return view
    }

    func updateNSView(_ nsView: GIFAnimationNSView, context: Context) {
        if nsView.currentURL != url {
            nsView.loadGIF(url: url)
        }
    }
}

/// AppKit view that renders animated GIF frames into a CALayer.
final class GIFAnimationNSView: NSView {
    private var imageLayer: CALayer?
    private var animationStatus: OSStatus = noErr
    private(set) var currentURL: URL?

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
        // Stop any running animation
        stopAnimation()
        currentURL = url

        // CGAnimateImageAtURLWithBlock calls back on each frame at the GIF's
        // native delay intervals. We render each frame into the CALayer.
        animationStatus = CGAnimateImageAtURLWithBlock(
            url as CFURL,
            nil
        ) { [weak self] _, cgImage, stop in
            guard let self else {
                stop.pointee = true
                return
            }
            self.imageLayer?.contents = cgImage
        }
    }

    func stopAnimation() {
        // Setting contents to nil stops rendering; the animation block's
        // stop pointer is handled via the weak self guard above.
        imageLayer?.contents = nil
        currentURL = nil
    }
}
