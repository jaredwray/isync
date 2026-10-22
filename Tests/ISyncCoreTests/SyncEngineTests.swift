import XCTest

@testable import ISyncCore

final class SyncEngineTests: XCTestCase {
    private func makeEngine(
        messages: (any MessageSource)? = nil,
        contacts: (any ContactSource)? = nil,
        api: any SyncAPI,
        store: any SyncStateStore,
        batchSize: Int = 2
    ) -> SyncEngine {
        SyncEngine(
            messageSource: messages,
            contactSource: contacts,
            api: api,
            stateStore: store,
            options: .init(messageBatchSize: batchSize, contactBatchSize: batchSize)
        )
    }

    func testUploadsMessagesInBatchesAndSavesTheCursor() async throws {
        let api = RecordingAPI()
        let store = InMemorySyncStateStore()
        let source = FakeMessageSource(count: 5)
        source.rows.withLock { $0[2].attributedBody = Data([0x01]) }

        let report = await makeEngine(messages: source, api: api, store: store).run()

        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(report.messagesUploaded, 5)
        XCTAssertEqual(report.messagesWithRawBody, 1, "the app status shows messages that the decoder cannot read")
        XCTAssertEqual(api.messageBatches.current, [[1, 2], [3, 4], [5]])
        XCTAssertEqual(try store.load().messageCursor, 5)
    }

    func testAFailedBatchDoesNotMoveTheCursorAndTheNextRunSendsItAgain() async throws {
        let api = RecordingAPI(failingMessageCalls: [2])
        let store = InMemorySyncStateStore()
        let engine = makeEngine(messages: FakeMessageSource(count: 5), api: api, store: store)

        let first = await engine.run()
        XCTAssertEqual(first.failures.map(\.part), [.messages])
        XCTAssertEqual(first.messagesUploaded, 2, "the report counts the batch that the API accepted")
        XCTAssertEqual(try store.load().messageCursor, 2)

        let second = await engine.run()
        XCTAssertTrue(second.succeeded)
        XCTAssertEqual(api.messageBatches.current, [[1, 2], [3, 4], [5]])
    }

    func testARunStopsAtTheROWIDFromItsStartWhenNewMessagesKeepArriving() async throws {
        let source = GrowingMessageSource(initialCount: 3)
        let api = RecordingAPI()
        let store = InMemorySyncStateStore()
        let engine = makeEngine(
            messages: source,
            contacts: FakeContactSource([Contact(id: "a")]),
            api: api,
            store: store,
            batchSize: 1
        )

        let first = await engine.run()
        let second = await engine.run()

        XCTAssertEqual(api.messageBatches.current.prefix(3), [[1], [2], [3]])
        XCTAssertEqual(first.messagesUploaded, 3, "rows that arrive during the run wait for the next run")
        XCTAssertEqual(first.contactsUploaded, 1, "the contact sync runs in the same run")
        XCTAssertGreaterThan(second.messagesUploaded, 0)
    }

    func testACursorAboveTheDatabaseGoesBackToZero() async throws {
        let api = RecordingAPI()
        let store = InMemorySyncStateStore(SyncState(messageCursor: 900))

        let report = await makeEngine(messages: FakeMessageSource(count: 3), api: api, store: store, batchSize: 10)
            .run()

        XCTAssertEqual(report.messagesUploaded, 3)
        XCTAssertEqual(try store.load().messageCursor, 3)
    }

    func testUploadsChangedContactsThenDeletesAndSkipsAnUnchangedSecondRun() async throws {
        let api = RecordingAPI()
        let store = InMemorySyncStateStore()
        let source = FakeContactSource([Contact(id: "a"), Contact(id: "b"), Contact(id: "c")])
        let engine = makeEngine(contacts: source, api: api, store: store)

        _ = await engine.run()
        source.cards.withLock { $0 = [Contact(id: "a", givenName: "Ana"), Contact(id: "b")] }
        let report = await engine.run()
        _ = await engine.run()

        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(report.contactsUploaded, 1)
        XCTAssertEqual(report.contactsDeleted, 1)
        XCTAssertEqual(
            api.contactUploads.current,
            [
                .init(ids: ["a", "b"], deleted: []),
                .init(ids: ["c"], deleted: []),
                .init(ids: ["a"], deleted: []),
                .init(ids: [], deleted: ["c"]),
            ])
        XCTAssertEqual(Set(try store.load().contactHashes.keys), ["a", "b"])
    }

    func testAFailedContactUploadKeepsTheOldStateAndTheNextRunSendsItAgain() async throws {
        // Call 1 sends the changed card. Call 2 sends the delete.
        for failingCall in [1, 2] {
            let initial = try ContactDiff.changes(current: [Contact(id: "a"), Contact(id: "b")], previousHashes: [:])
            let store = InMemorySyncStateStore(SyncState(contactHashes: initial.hashes))
            let api = RecordingAPI(failingContactCalls: [failingCall])
            let source = FakeContactSource([Contact(id: "a", givenName: "Ana")])
            let engine = makeEngine(contacts: source, api: api, store: store)

            let failed = await engine.run()
            let hashesAfterFailure = try store.load().contactHashes
            let recovered = await engine.run()

            XCTAssertEqual(failed.failures.map(\.part), [.contacts], "call \(failingCall)")
            XCTAssertEqual(failed.contactsUploaded, failingCall == 1 ? 0 : 1, "call \(failingCall)")
            XCTAssertEqual(hashesAfterFailure["b"], initial.hashes["b"], "call \(failingCall): b is not deleted yet")
            if failingCall == 1 {
                XCTAssertEqual(hashesAfterFailure["a"], initial.hashes["a"], "the changed card is not marked as sent")
            }
            XCTAssertTrue(recovered.succeeded, "call \(failingCall)")
            XCTAssertEqual(api.contactUploads.current.last, .init(ids: [], deleted: ["b"]), "call \(failingCall)")
            XCTAssertEqual(Set(try store.load().contactHashes.keys), ["a"], "call \(failingCall)")
        }
    }

    func testAnEmptyContactSourceDoesNotDeleteSyncedCards() async throws {
        let api = RecordingAPI()
        let store = InMemorySyncStateStore(SyncState(contactHashes: ["a": "1", "b": "2"]))

        let report = await makeEngine(contacts: FakeContactSource([]), api: api, store: store).run()

        XCTAssertEqual(report.failures.map(\.part), [.contacts])
        XCTAssertEqual(api.contactUploads.current, [])
        XCTAssertEqual(try store.load().contactHashes.count, 2)
    }

    func testAMessageFailureDoesNotStopTheContactSync() async throws {
        let api = RecordingAPI(failingMessageCalls: [1])
        let engine = makeEngine(
            messages: FakeMessageSource(count: 1),
            contacts: FakeContactSource([Contact(id: "a")]),
            api: api,
            store: InMemorySyncStateStore()
        )

        let report = await engine.run()

        XCTAssertEqual(report.failures.map(\.part), [.messages])
        XCTAssertEqual(report.contactsUploaded, 1)
    }

    func testASecondRunDuringARunIsSkipped() async throws {
        let api = BlockingAPI()
        let engine = makeEngine(messages: FakeMessageSource(count: 1), api: api, store: InMemorySyncStateStore())

        let first = Task { await engine.run() }
        await api.waitUntilCalled()
        let second = await engine.run()
        api.release()
        let firstReport = await first.value

        XCTAssertTrue(second.skipped)
        XCTAssertTrue(firstReport.succeeded)
    }
}

/// A Messages database that gets a new row each time the sync reads a batch, up to 50 rows.
private final class GrowingMessageSource: MessageSource, @unchecked Sendable {
    private let rows: Locked<[Message]>

    init(initialCount: Int) {
        rows = Locked((1...initialCount).map { Message(rowID: Int64($0), guid: "guid-\($0)") })
    }

    func latestRowID() throws -> Int64 {
        rows.current.last?.rowID ?? 0
    }

    func messages(after cursor: Int64, limit: Int) throws -> [Message] {
        rows.withLock { rows in
            let batch = Array(rows.filter { $0.rowID > cursor }.prefix(limit))
            if let last = rows.last, last.rowID < 50 {
                rows.append(Message(rowID: last.rowID + 1, guid: "guid-\(last.rowID + 1)"))
            }
            return batch
        }
    }
}

/// An API that holds the first message upload until the test releases it.
private final class BlockingAPI: SyncAPI, @unchecked Sendable {
    private let called = AsyncStream<Void>.makeStream()
    private let gate = Locked<CheckedContinuation<Void, Never>?>(nil)
    private let released = Locked(false)

    func upload(messages: [Message], deviceID: String) async throws {
        await withCheckedContinuation { continuation in
            let releaseNow = released.withLock { isReleased -> Bool in
                if !isReleased { gate.withLock { $0 = continuation } }
                return isReleased
            }
            called.continuation.yield()
            if releaseNow { continuation.resume() }
        }
    }

    func upload(contacts: [Contact], deletedContactIDs: [String], deviceID: String) async throws {}

    func waitUntilCalled() async {
        var iterator = called.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() {
        let continuation = released.withLock { isReleased -> CheckedContinuation<Void, Never>? in
            isReleased = true
            return gate.withLock { stored in
                defer { stored = nil }
                return stored
            }
        }
        continuation?.resume()
    }
}
