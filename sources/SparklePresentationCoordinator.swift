import AppKit

@MainActor
protocol AppActivationControlling {
    var activationPolicy: NSApplication.ActivationPolicy { get }
    func setActivationPolicy(_ policy: NSApplication.ActivationPolicy)
    func activate(ignoringOtherApps: Bool)
}

@MainActor
struct NSAppActivationController: AppActivationControlling {
    var activationPolicy: NSApplication.ActivationPolicy {
        NSApp.activationPolicy()
    }

    func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        _ = NSApp.setActivationPolicy(policy)
    }

    func activate(ignoringOtherApps: Bool) {
        NSApp.activate(ignoringOtherApps: ignoringOtherApps)
    }
}

/// Coordinates how Sparkle UI is surfaced for a menu-bar accessory app.
/// No-update alerts can stay dockless, but an actual update session needs a
/// temporary promotion back to a regular foreground app so Sparkle's update
/// window is visible and easy to return to.
@MainActor
final class SparklePresentationCoordinator {
    private let app: any AppActivationControlling
    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    init(app: any AppActivationControlling = NSAppActivationController()) {
        self.app = app
    }

    func beginUserInitiatedCheck() {
        app.activate(ignoringOtherApps: true)
    }

    func willShowModalAlert() {
        app.activate(ignoringOtherApps: true)
    }

    func willShowUpdate() {
        if previousActivationPolicy == nil, app.activationPolicy == .accessory {
            previousActivationPolicy = .accessory
            app.setActivationPolicy(.regular)
        }
        app.activate(ignoringOtherApps: true)
    }

    func finishUpdateSession() {
        guard let previousActivationPolicy else { return }
        app.setActivationPolicy(previousActivationPolicy)
        self.previousActivationPolicy = nil
    }
}
