import ServiceManagement

/// Starts the app when the person logs in, with `SMAppService`.
@MainActor
public enum LoginItem {
    /// True when the app is registered. This includes the state where macOS waits for the
    /// person to approve the item in System Settings.
    public static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    /// True when macOS waits for the person to approve the item in System Settings.
    public static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Opens System Settings > General > Login Items.
    public static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
