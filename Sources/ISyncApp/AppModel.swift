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
    /// The last error from Settings, such as an invalid URL.
    var settingsError: String?

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
            lastReport = await engine.run()
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

    /// Returns false and sets `settingsError` when the configuration is not valid.
    @discardableResult
    func save(_ newConfiguration: SyncConfiguration) -> Bool {
        do {
            try configurationStore.save(newConfiguration)
            let intervalChanged = newConfiguration.syncIntervalMinutes != configuration.syncIntervalMinutes
            configuration = newConfiguration
            settingsError = nil
            if intervalChanged {
                scheduler?.start(intervalMinutes: newConfiguration.syncIntervalMinutes)
            }
            return true
        } catch {
            settingsError = String(describing: error)
            return false
        }
    }

    func saveToken(_ token: String) {
        do {
            try tokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
            settingsError = nil
        } catch {
            settingsError = String(describing: error)
        }
        refreshStatus()
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
