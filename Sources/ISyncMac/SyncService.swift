import Foundation
import ISyncCore

/// Builds a `SyncEngine` from the saved configuration for one run.
public enum SyncService {
    public enum SetupError: Error, CustomStringConvertible {
        case noAPIURL

        public var description: String {
            "Set the API URL in Settings before the first sync."
        }
    }

    /// - Parameters:
    ///   - token: The API token. Nil sends no Authorization header.
    ///   - api: Replaces the HTTP API, for a dry run.
    ///   - stateStore: Replaces the state file, for a dry run.
    public static func makeEngine(
        configuration: SyncConfiguration,
        token: String?,
        api: (any SyncAPI)? = nil,
        stateStore: (any SyncStateStore)? = nil
    ) throws -> SyncEngine {
        let resolvedAPI: any SyncAPI
        if let api {
            resolvedAPI = api
        } else {
            guard let baseURL = configuration.apiBaseURL else { throw SetupError.noAPIURL }
            resolvedAPI = try HTTPSyncAPI(baseURL: baseURL, token: token, userAgent: "isync/\(ISyncVersion.current)")
        }
        return SyncEngine(
            messageSource: configuration.syncMessages ? MessagesDatabase() : nil,
            contactSource: configuration.syncContacts ? SystemContactSource() : nil,
            api: resolvedAPI,
            stateStore: stateStore ?? FileSyncStateStore(),
            options: .init(
                messageBatchSize: configuration.messageBatchSize,
                contactBatchSize: configuration.contactBatchSize
            )
        )
    }

    /// The lock file that stops two processes, such as the app and isync-cli, from a sync at the same time.
    /// Both processes write the same state file.
    public static var lockURL: URL { AppPaths.directory.appending(path: "sync.lock") }

    /// Runs the engine while this process holds the sync lock. If a different process holds
    /// the lock, the result is a skipped report.
    public static func runExclusive(_ engine: SyncEngine, lockURL: URL = SyncService.lockURL) async -> SyncReport {
        let lock: FileLock
        do {
            guard let acquired = try FileLock(url: lockURL) else {
                var report = SyncReport(startedAt: Date())
                report.skipped = true
                return report
            }
            lock = acquired
        } catch {
            var report = SyncReport(startedAt: Date())
            report.failures = [SyncFailure(part: .state, reason: "Cannot open the sync lock. \(error)")]
            return report
        }
        let report = await engine.run()
        lock.unlock()
        return report
    }

    /// False only when macOS blocks access to chat.db, which means that the app needs Full Disk
    /// Access. A Mac with no chat.db is not a permission problem.
    public static func canReadMessages() -> Bool {
        do {
            _ = try MessagesDatabase().latestRowID()
            return true
        } catch MessagesDatabaseError.accessDenied {
            return false
        } catch {
            return true
        }
    }
}
