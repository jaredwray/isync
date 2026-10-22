import Foundation

/// Sends new messages and changed contacts to the API.
///
/// Delivery is at least once. The engine saves its progress only after the API
/// accepts a batch, so a failed batch goes again in the next run.
public actor SyncEngine {
    public struct Options: Sendable {
        public var messageBatchSize: Int
        public var contactBatchSize: Int

        public init(messageBatchSize: Int = 500, contactBatchSize: Int = 200) {
            precondition(messageBatchSize > 0 && contactBatchSize > 0, "batch sizes must be positive")
            self.messageBatchSize = messageBatchSize
            self.contactBatchSize = contactBatchSize
        }
    }

    public enum ContactSafetyError: Error, CustomStringConvertible {
        case emptySource(previousCount: Int)

        public var description: String {
            switch self {
            case let .emptySource(previousCount):
                "Contacts returned no cards, but \(previousCount) cards synced before. "
                    + "The sync did not delete them. Make sure that isync can read Contacts."
            }
        }
    }

    private let messageSource: (any MessageSource)?
    private let contactSource: (any ContactSource)?
    private let api: any SyncAPI
    private let stateStore: any SyncStateStore
    private let options: Options
    private let now: @Sendable () -> Date
    private var isRunning = false

    /// - Parameters:
    ///   - messageSource: Nil turns off the message sync.
    ///   - contactSource: Nil turns off the contact sync.
    public init(
        messageSource: (any MessageSource)?,
        contactSource: (any ContactSource)?,
        api: any SyncAPI,
        stateStore: any SyncStateStore,
        options: Options = Options(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.messageSource = messageSource
        self.contactSource = contactSource
        self.api = api
        self.stateStore = stateStore
        self.options = options
        self.now = now
    }

    /// Runs one sync. If a run is in progress, this returns a skipped report.
    /// A failure in one part does not stop the other part.
    public func run() async -> SyncReport {
        var report = SyncReport(startedAt: now())
        guard !isRunning else {
            report.skipped = true
            return report
        }
        isRunning = true
        defer { isRunning = false }

        var state: SyncState
        do {
            state = try stateStore.load()
        } catch {
            report.failures.append(SyncFailure(part: .state, reason: "Cannot load the sync state: \(error)"))
            report.finishedAt = now()
            return report
        }

        if let messageSource {
            do {
                report.messagesUploaded = try await syncMessages(from: messageSource, state: &state)
            } catch {
                report.failures.append(SyncFailure(part: .messages, reason: String(describing: error)))
            }
        }

        if let contactSource {
            do {
                let counts = try await syncContacts(from: contactSource, state: &state)
                report.contactsUploaded = counts.uploaded
                report.contactsDeleted = counts.deleted
            } catch {
                report.failures.append(SyncFailure(part: .contacts, reason: String(describing: error)))
            }
        }

        report.finishedAt = now()
        Log.info(
            "Sync finished: \(report.messagesUploaded) messages, \(report.contactsUploaded) contacts, "
                + "\(report.contactsDeleted) deletes, \(report.failures.count) failures."
        )
        return report
    }

    private func syncMessages(from source: any MessageSource, state: inout SyncState) async throws -> Int {
        let latest = try source.latestRowID()
        if state.messageCursor > latest {
            // The database is new, for example after a restore. Send all messages
            // again. The API drops repeated messages by GUID.
            Log.info("Message cursor \(state.messageCursor) is above ROWID \(latest). The cursor goes back to 0.")
            state.messageCursor = 0
            try stateStore.save(state)
        }

        var uploaded = 0
        while true {
            try Task.checkCancellation()
            let batch = try source.messages(after: state.messageCursor, limit: options.messageBatchSize)
            guard let last = batch.last else { break }
            try await api.upload(messages: batch, deviceID: state.deviceID)
            state.messageCursor = last.rowID
            try stateStore.save(state)
            uploaded += batch.count
            if batch.count < options.messageBatchSize { break }
        }
        state.lastMessageSync = now()
        try stateStore.save(state)
        return uploaded
    }

    private func syncContacts(
        from source: any ContactSource,
        state: inout SyncState
    ) async throws -> (uploaded: Int, deleted: Int) {
        let current = try await source.contacts()
        if current.isEmpty && !state.contactHashes.isEmpty {
            throw ContactSafetyError.emptySource(previousCount: state.contactHashes.count)
        }
        let changes = try ContactDiff.changes(current: current, previousHashes: state.contactHashes)

        var uploaded = 0
        for batch in changes.upserts.chunked(into: options.contactBatchSize) {
            try Task.checkCancellation()
            try await api.upload(contacts: Array(batch), deletedContactIDs: [], deviceID: state.deviceID)
            for contact in batch {
                state.contactHashes[contact.id] = changes.hashes[contact.id]
            }
            try stateStore.save(state)
            uploaded += batch.count
        }

        var deleted = 0
        for batch in changes.deletedIDs.chunked(into: options.contactBatchSize) {
            try Task.checkCancellation()
            try await api.upload(contacts: [], deletedContactIDs: Array(batch), deviceID: state.deviceID)
            for id in batch {
                state.contactHashes[id] = nil
            }
            try stateStore.save(state)
            deleted += batch.count
        }

        state.lastContactSync = now()
        try stateStore.save(state)
        return (uploaded, deleted)
    }
}

extension Array {
    func chunked(into size: Int) -> [ArraySlice<Element>] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}
