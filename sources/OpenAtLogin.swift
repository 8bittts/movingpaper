import ServiceManagement

/// What the status menu shows for the login item.
enum LoginItemStatus: Equatable {
    case enabled
    case disabled
    /// Registered, but the user has not approved it or revoked approval in
    /// System Settings > General > Login Items.
    case requiresApproval
}

/// Login-item registration for the menu-bar extra.
/// `SMAppService.mainApp` is the supported login-item API.
enum OpenAtLogin {
    static var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }

    /// Turn the login item on or off. Approval is the user's to give, so a login
    /// item waiting on it opens the Login Items settings instead: registering
    /// again only fails with `kSMErrorLaunchDeniedByUser`.
    static func toggle() throws {
        switch status {
        case .enabled:
            try SMAppService.mainApp.unregister()
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        case .disabled:
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}
