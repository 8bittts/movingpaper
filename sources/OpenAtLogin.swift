import ServiceManagement

/// Login-item registration for the menu-bar extra.
/// `SMAppService.mainApp` is the supported login-item API.
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
