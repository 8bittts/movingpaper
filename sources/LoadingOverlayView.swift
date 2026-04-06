import AppKit
import SwiftUI

// MARK: - Brand Palette (night sky)

private enum Brand {
    static let bg = Color(red: 0.04, green: 0.06, blue: 0.14)
    static let accent = Color(red: 0.55, green: 0.65, blue: 0.90)
    static let textDim = Color(white: 0.68)
    static let textBright = Color(white: 1.0)
    static let track = Color(white: 0.18)
}

// MARK: - SwiftUI View

struct LoadingOverlayView: View {
    let message: String
    let progress: Double?

    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(spacing: 10) {
            shimmerText
            if let progress {
                progressBar(value: progress)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(pill)
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    // Text with a sheen that sweeps left-to-right
    private var shimmerText: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(Brand.textDim)
            .overlay(sheen.mask(textMask))
    }

    private var textMask: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
    }

    private var sheen: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let band = w * 0.45
            LinearGradient(
                colors: [.clear, Brand.textBright, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band)
            .offset(x: -band + phase * (w + band))
        }
    }

    private func progressBar(value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.track)
                Capsule()
                    .fill(Brand.accent)
                    .frame(width: max(4, geo.size.width * value))
                    .animation(.easeInOut(duration: 0.3), value: value)
            }
        }
        .frame(width: 180, height: 3)
    }

    private var pill: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Brand.bg.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Brand.accent.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
    }
}

// MARK: - Panel Controller

@MainActor
final class LoadingOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    func show(message: String, progress: Double? = nil) {
        let content = LoadingOverlayView(message: message, progress: progress)

        if let hostingView {
            hostingView.rootView = AnyView(content)
            resizePanel()
            return
        }

        let hosting = NSHostingView(rootView: AnyView(content))
        let size = hosting.fittingSize
        let fixedWidth = max(size.width, 220)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: fixedWidth, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        hosting.frame = window.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(hosting)

        centerOnScreen(window)

        window.alphaValue = 0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        self.panel = window
        self.hostingView = hosting
    }

    func hide() {
        guard let panel else { return }
        // Nil references immediately so a concurrent show() creates a fresh panel
        // instead of updating the one being faded out.
        self.panel = nil
        self.hostingView = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        })
    }

    private func resizePanel() {
        guard let panel, let hostingView else { return }
        let size = hostingView.fittingSize
        let fixedWidth = max(size.width, 220)
        panel.setContentSize(NSSize(width: fixedWidth, height: size.height))
        centerOnScreen(panel)
    }

    private func centerOnScreen(_ window: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - window.frame.width / 2
        let y = screen.frame.midY - window.frame.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
