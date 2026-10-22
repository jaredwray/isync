import AppKit
import Foundation
import ISyncCore
import ISyncMac
import Observation

/// The state that the menu and the settings window show.
@MainActor
@Observable
final class AppModel {
    private(set) var configuration: SyncConfiguration
    private(set) var lastReport: SyncReport?
    private(set) var isSyncing = false
    private(set) var hasToken = false
    private(set) var canReadMessages = false
    private(set) var canReadContacts = false
    private(set) var launchesAtLogin = false
    private(set) var loginItemNeedsApproval = false
    /// The last error from Settings, such as an invalid URL.
    var settingsError: String?
    /// A note about the last save, such as a removed token.
    private(set) var settingsNotice: String?

    private let configurationStore = ConfigurationStore()
    private let tokenStore = KeychainTokenStore()
    @ObservationIgnored private var scheduler: BackgroundSyncScheduler?

    init() {
        do {
            configuration = try configurationStore.load()
        } catch {
            configuration = SyncConfiguration()
            settingsError = "Cannot read the settings file. The app uses the defaults. \(error)"
        }
        refreshStatus()
        scheduler = BackgroundSyncScheduler { [weak self] in
            await self?.syncNow() ?? false
        }
        scheduler?.start(intervalMinutes: configuration.syncIntervalMinutes)
        Task { await syncNow() }
    }

    // MARK: - Sync

    /// Returns false when it did not run because a sync is in progress.
    @discardableResult
    func syncNow() async -> Bool {
        guard !isSyncing else { return false }
        guard configuration.apiBaseURL != nil else {
            refreshStatus()
            return true
        }
        isSyncing = true
        defer { isSyncing = false }

        let configuration = configuration
        let token: String?
        do {
            token = try tokenStore.read()
        } catch {
            lastReport = Self.failedReport(part: .state, reason: String(describing: error))
            return true
        }
        do {
            let engine = try SyncService.makeEngine(configuration: configuration, token: token)
            let report = await SyncService.runExclusive(engine)
            // A skipped run means that a different process, such as isync-cli, holds the sync lock.
            if report.skipped { return false }
            lastReport = report
        } catch {
            lastReport = Self.failedReport(part: .state, reason: String(describing: error))
        }
        refreshStatus()
        return true
    }

    private static func failedReport(part: SyncFailure.Part, reason: String) -> SyncReport {
        var report = SyncReport(startedAt: Date())
        report.failures = [SyncFailure(part: part, reason: reason)]
        return report
    }

    var statusSummary: String {
        if isSyncing { return "Syncing…" }
        if configuration.apiBaseURL == nil { return "Set the API URL in Settings" }
        guard let report = lastReport else { return "No sync yet" }
        let time = report.finishedAt.formatted(date: .omitted, time: .shortened)
        if report.succeeded {
            return "Last sync \(time): \(report.messagesUploaded) messages, "
                + "\(report.contactsUploaded + report.contactsDeleted) contact changes"
        }
        return "Last sync \(time) failed"
    }

    // MARK: - Settings

    /// Saves the settings and an optional new token. Returns false and sets `settingsError` on failure.
    ///
    /// The order keeps private data safe:
    /// 1. Validate the configuration.
    /// 2. If the server origin changes, remove the old token, so that it does not go to the new server.
    /// 3. If the URL changes, reset the sync progress, so that the new server gets all data.
    /// 4. Save the configuration, then the new token.
    @discardableResult
    func applySettings(_ newConfiguration: SyncConfiguration, token rawToken: String) -> Bool {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousURL = configuration.apiBaseURL
        let urlChanged = previousURL != nil && newConfiguration.apiBaseURL != previousURL
        let originChanged = urlChanged && Self.origin(of: newConfiguration.apiBaseURL) != Self.origin(of: previousURL)
        var notes: [String] = []
        do {
            try newConfiguration.validate()
            if urlChanged && isSyncing {
                settingsError = "A sync is in progress. Save the new URL after it finishes."
                return false
            }
            if originChanged && token.isEmpty && tokenStore.exists() {
                try tokenStore.delete()
                notes.append(
                    "The server changed, so the app removed the old token. Enter the token for the new server.")
            }
            if urlChanged {
                try Self.resetSyncProgress()
                notes.append("The URL changed, so the next sync sends all data to the new URL.")
            }
            try configurationStore.save(newConfiguration)
            let intervalChanged = newConfiguration.syncIntervalMinutes != configuration.syncIntervalMinutes
            configuration = newConfiguration
            if intervalChanged {
                scheduler?.start(intervalMinutes: newConfiguration.syncIntervalMinutes)
            }
            if !token.isEmpty {
                try tokenStore.save(token)
            }
            settingsError = nil
            settingsNotice = notes.isEmpty ? nil : notes.joined(separator: " ")
            refreshStatus()
            return true
        } catch {
            settingsError = String(describing: error)
            refreshStatus()
            return false
        }
    }

    /// "scheme://host:port" in lowercase, or nil.
    private static func origin(of url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: false) else {
            return nil
        }
        return "\(scheme)://\(host.lowercased()):\(url.port.map(String.init) ?? "")"
    }

    /// Keeps the device ID and clears the message cursor and the contact hashes.
    private static func resetSyncProgress() throws {
        let store = FileSyncStateStore()
        guard let state = try store.loadIfPresent() else { return }
        try store.save(SyncState(deviceID: state.deviceID))
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            settingsError = "Cannot change the login item. \(error)"
        }
        refreshStatus()
    }

    func requestContactsAccess() async {
        do {
            _ = try await SystemContactSource.requestAccess()
        } catch {
            settingsError = "Cannot get access to Contacts. \(error)"
        }
        refreshStatus()
    }

    func openPrivacySettings(_ pane: PrivacyPane) {
        NSWorkspace.shared.open(pane.url)
    }

    func refreshStatus() {
        hasToken = tokenStore.exists()
        canReadMessages = SyncService.canReadMessages()
        canReadContacts = SystemContactSource.isAuthorized
        launchesAtLogin = LoginItem.isEnabled
        loginItemNeedsApproval = LoginItem.needsApproval
    }

    func openLoginItemsSettings() {
        LoginItem.openSettings()
    }

    enum PrivacyPane {
        case fullDiskAccess
        case contacts

        var url: URL {
            switch self {
            case .fullDiskAccess:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
            case .contacts:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")!
            }
        }
    }
}
