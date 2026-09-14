import ServiceManagement

/// Login-item registration for the menu-bar extra.
/// `SMAppService.mainApp` is the supported API on macOS 13+ (deployment is 15).
enum OpenAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
