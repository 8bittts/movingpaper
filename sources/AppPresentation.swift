import AppKit

@MainActor
enum AppPresentation {
    static func promoteToForeground() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func returnToAccessory() {
        NSApp.setActivationPolicy(.accessory)
    }

    static func withForegroundActivation<T>(_ operation: () throws -> T) rethrows -> T {
        promoteToForeground()
        defer { returnToAccessory() }
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
            alert.window.level = .floating
            alert.runModal()
        }
    }

    static func showWarningAlert(title: String, message: String) {
        showAlert(title: title, message: message, style: .warning)
    }
}
