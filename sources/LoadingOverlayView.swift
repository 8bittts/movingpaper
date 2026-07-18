import AppKit
import SwiftUI

// MARK: - Brand Palette (night sky)

private enum Brand {
    static let bg = Color(red: 0.04, green: 0.06, blue: 0.14)
    static let accent = Color(red: 0.55, green: 0.65, blue: 0.90)
    static let textDim = Color(white: 0.68)
    static let textBright = Color(white: 1.0)
}

// MARK: - SwiftUI View

struct LoadingOverlayView: View {
    let message: String
    let progress: Double?

    // Honor the system accessibility preferences: no sweeping motion under
    // Reduce Motion, no translucency under Reduce Transparency. NSHostingView
    // forwards both system values into SwiftUI automatically.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
            // Reduce Motion: leave the sheen parked and show static text.
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    // Text with a sheen that sweeps left-to-right. Under Reduce Motion the sweep
    // is dropped and the text is shown statically at full brightness.
    private var shimmerText: some View {
        Text(message)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(reduceMotion ? Brand.textBright : Brand.textDim)
            .overlay {
                if !reduceMotion {
                    sheen.mask(textMask)
                }
            }
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

    // Standard determinate indicator — brings built-in Reduce Motion handling,
    // correct layout direction, and VoiceOver progress value for free.
    private func progressBar(value: Double) -> some View {
        ProgressView(value: value)
            .progressViewStyle(.linear)
            .tint(Brand.accent)
            .frame(width: 180)
    }

    private var pill: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Brand.bg.opacity(reduceTransparency ? 1.0 : 0.92))
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
    /// The display to center on (nil → main screen, for all-desktops changes).
    private var targetScreen: NSScreen?

    func show(message: String, progress: Double? = nil, on screen: NSScreen? = nil) {
        targetScreen = screen
        let content = LoadingOverlayView(message: message, progress: progress)

        if let hostingView {
            hostingView.rootView = AnyView(content)
            resizePanel()
            return
        }

        // First appearance of this overlay: announce it for VoiceOver, since the
        // borderless nonactivating panel never takes focus on its own.
        announce(message)

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
                panel.close()
            }
        })
    }

    /// Post a VoiceOver announcement for the transient overlay status. Best-effort
    /// for an accessory app, but never worse than the current silence.
    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func resizePanel() {
        guard let panel, let hostingView else { return }
        let size = hostingView.fittingSize
        let fixedWidth = max(size.width, 220)
        panel.setContentSize(NSSize(width: fixedWidth, height: size.height))
        centerOnScreen(panel)
    }

    private func centerOnScreen(_ window: NSPanel) {
        guard let screen = targetScreen ?? NSScreen.main else { return }
        let x = screen.frame.midX - window.frame.width / 2
        let y = screen.frame.midY - window.frame.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
