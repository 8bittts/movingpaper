import AppKit
import SwiftUI

// MARK: - SwiftUI View

/// Transient status for a wallpaper that is loading: a label over a system
/// progress indicator, on the platform's own surface.
///
/// Everything here is a system style. Text styles, vibrant foreground colors and
/// the standard `ProgressView` follow Dynamic Type sizes, light and dark
/// appearance, Increase Contrast, Reduce Transparency and Reduce Motion with no
/// code of our own.
struct LoadingOverlayView: View {
    let message: String
    let progress: Double?

    var body: some View {
        VStack(spacing: 10) {
            Text(message)
                .font(.headline)
                .foregroundStyle(.primary)
                .monospacedDigit()
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 180)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }
}

// MARK: - Panel Controller

@MainActor
final class LoadingOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<LoadingOverlayView>?
    /// The display to center on (nil → main screen, for all-desktops changes).
    private var targetScreen: NSScreen?
    /// Last VoiceOver key so percent ticks do not re-announce.
    private var lastAnnouncedKey: String?

    func show(message: String, progress: Double? = nil, on screen: NSScreen? = nil) {
        targetScreen = screen
        let content = LoadingOverlayView(message: message, progress: progress)

        announceIfNeeded(message)

        if let hostingView {
            hostingView.rootView = content
            resizePanel()
            return
        }

        let hosting = NSHostingView(rootView: content)
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        // The system draws the shadow around the surface's rounded shape.
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        // NSPanel defaults to hiding on deactivate; the overlay must stay up
        // while the user works in another app during a download.
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        window.contentView = Self.makeSurface(containing: hosting)

        centerOnScreen(window)

        window.orderFront(nil)
        if Self.reduceMotion {
            window.alphaValue = 1
        } else {
            window.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
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
        lastAnnouncedKey = nil
        if Self.reduceMotion {
            panel.orderOut(nil)
            panel.close()
            return
        }
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

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Announce overlay copy when the *kind* of message changes, not every percent.
    private func announceIfNeeded(_ message: String) {
        let key = message.replacingOccurrences(of: #"\d+%"#, with: "%", options: .regularExpression)
        guard key != lastAnnouncedKey else { return }
        lastAnnouncedKey = key
        announce(message)
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
        panel.setContentSize(hostingView.fittingSize)
        centerOnScreen(panel)
    }

    private static let cornerRadius: CGFloat = 20

    /// The Liquid Glass surface behind the content. An AppKit view because it
    /// composites against what is behind the window; a SwiftUI glass effect in a
    /// transparent panel has nothing to sample and draws a flat slab.
    private static func makeSurface(containing content: NSView) -> NSView {
        let glass = NSGlassEffectView()
        // Regular, not clear: the overlay carries text, and regular glass keeps
        // text legible over any wallpaper (HIG: Materials).
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        return glass
    }

    private func centerOnScreen(_ window: NSPanel) {
        guard let screen = targetScreen ?? NSScreen.main else { return }
        let x = screen.frame.midX - window.frame.width / 2
        let y = screen.frame.midY - window.frame.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
