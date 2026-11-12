import AppKit

/// The one owner of the app's activation policy.
///
/// The app is an accessory (`LSUIElement`): no Dock icon and no app menu. Some
/// surfaces need a regular app to take focus — alerts, the open panel, the Photos
/// picker, Sparkle's windows — and the Dock session gives a way in when the
/// menu-bar extra is hidden (HIG: "Avoid relying on the presence of menu bar
/// extras"). Each surface holds a reason while it is up; the app is regular while
/// any reason is held and returns to accessory only when the last one ends, so
/// closing one surface cannot drop the Dock icon from under another.
@MainActor
enum AppPresentation {
    enum Reason: Hashable, CaseIterable {
        /// A modal alert or open panel.
        case modal
        /// The Photos picker window.
        case photosPicker
        /// A Photos shuffle, which may raise the Photos authorization prompt.
        case photosShuffle
        /// A Sparkle update session.
        case updater
        /// The Dock fallback started when the app is opened while it runs.
        case dockSession
    }

    private(set) static var holds = Holds()

    /// Hold `reason` and bring the app forward.
    static func begin(_ reason: Reason) {
        holds.begin(reason)
        applyPolicy()
        NSApp.activate()
    }

    /// Release one hold of `reason`. Extra calls are ignored.
    static func end(_ reason: Reason) {
        holds.end(reason)
        applyPolicy()
    }

    static func isHeld(_ reason: Reason) -> Bool {
        holds.contains(reason)
    }

    static func withForegroundActivation<T>(_ operation: () throws -> T) rethrows -> T {
        begin(.modal)
        defer { end(.modal) }
        return try operation()
    }

    static func showAlert(
        title: String,
        message: String,
        style: NSAlert.Style = .informational
    ) {
        withForegroundActivation {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = style
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private static func applyPolicy() {
        let wanted = holds.activationPolicy
        if NSApp.activationPolicy() != wanted {
            NSApp.setActivationPolicy(wanted)
        }
    }

    /// Counted holds per reason. A value type so tests can drive it without `NSApp`.
    struct Holds: Equatable {
        private var counts: [Reason: Int] = [:]

        var isEmpty: Bool { counts.isEmpty }

        var activationPolicy: NSApplication.ActivationPolicy {
            isEmpty ? .accessory : .regular
        }

        func contains(_ reason: Reason) -> Bool {
            counts[reason] != nil
        }

        mutating func begin(_ reason: Reason) {
            counts[reason, default: 0] += 1
        }

        mutating func end(_ reason: Reason) {
            guard let count = counts[reason] else { return }
            counts[reason] = count > 1 ? count - 1 : nil
        }
    }
}
