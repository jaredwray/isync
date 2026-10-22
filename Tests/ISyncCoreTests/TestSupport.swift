import Foundation
import XCTest

@testable import ISyncCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A value that tests share across tasks.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }

    var current: Value { withLock { $0 } }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "isync-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Builds a small database with the chat.db tables that the reader uses.
struct ChatDatabaseFixture {
    let url: URL
    private let database: SQLiteDatabase

    init(includeOptionalColumns: Bool = true) throws {
        url = try temporaryDirectory().appending(path: "chat.db")
        database = try SQLiteDatabase(path: url.path(percentEncoded: false), readOnly: false)
        let optional =
            includeOptionalColumns
            ? """
            , attributedBody BLOB, date_edited INTEGER DEFAULT 0, date_retracted INTEGER DEFAULT 0,
            associated_message_guid TEXT, associated_message_type INTEGER DEFAULT 0, thread_originator_guid TEXT
            """ : ""
        try database.execute(
            """
            CREATE TABLE handle (ROWID INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE, id TEXT NOT NULL, service TEXT);
            CREATE TABLE chat (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT UNIQUE NOT NULL, style INTEGER,
                chat_identifier TEXT, service_name TEXT, display_name TEXT);
            CREATE TABLE message (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT UNIQUE NOT NULL, text TEXT,
                handle_id INTEGER DEFAULT 0, service TEXT, date INTEGER, date_read INTEGER, date_delivered INTEGER,
                is_from_me INTEGER DEFAULT 0, item_type INTEGER DEFAULT 0\(optional));
            CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER, PRIMARY KEY (chat_id, message_id));
            CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER, UNIQUE (chat_id, handle_id));
            CREATE TABLE attachment (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT UNIQUE NOT NULL,
                filename TEXT, mime_type TEXT, transfer_name TEXT, total_bytes INTEGER DEFAULT 0);
            CREATE TABLE message_attachment_join (message_id INTEGER, attachment_id INTEGER);
            """)
    }

    func execute(_ sql: String) throws {
        try database.execute(sql)
    }
}

/// Builds an `attributedBody` value in the shape that Messages writes.
func attributedBody(_ text: String, mutable: Bool = false) -> Data {
    var bytes: [UInt8] =
        [0x04, 0x0B] + Array("streamtyped".utf8) + [0x81, 0xE8, 0x03, 0x84, 0x01, 0x40, 0x84, 0x84, 0x84]
    bytes += [0x12] + Array("NSAttributedString".utf8) + [0x00, 0x84, 0x84, 0x08] + Array("NSObject".utf8)
    bytes += [0x00, 0x85, 0x92, 0x84, 0x84, 0x84]
    if mutable {
        bytes += [0x0F] + Array("NSMutableString".utf8) + [0x01, 0x84, 0x84]
    }
    bytes += [0x08] + Array("NSString".utf8) + [0x01, mutable ? 0x95 : 0x94, 0x84, 0x01, 0x2B]
    let utf8 = Array(text.utf8)
    if utf8.count < 0x80 {
        bytes.append(UInt8(utf8.count))
    } else {
        bytes += [0x81, UInt8(utf8.count & 0xFF), UInt8(utf8.count >> 8)]
    }
    bytes += utf8
    bytes += [0x86, 0x84, 0x02, 0x69, 0x49, 0x01]
    return Data(bytes)
}

extension Data {
    var hexLiteral: String { "X'" + map { String(format: "%02X", $0) }.joined() + "'" }
}

// MARK: - Fakes

final class FakeMessageSource: MessageSource, @unchecked Sendable {
    let rows: Locked<[Message]>
    let sequence: Locked<Int64?>

    init(count: Int) {
        rows = Locked((0..<count).map { Message(rowID: Int64($0 + 1), guid: "guid-\($0 + 1)") })
        sequence = Locked(nil)
    }

    func latestRowID() throws -> Int64 {
        sequence.current ?? rows.current.last?.rowID ?? 0
    }

    func messages(after cursor: Int64, limit: Int) throws -> [Message] {
        Array(rows.current.filter { $0.rowID > cursor }.prefix(limit))
    }
}

struct FakeContactSource: ContactSource {
    let cards: Locked<[Contact]>

    init(_ cards: [Contact]) {
        self.cards = Locked(cards)
    }

    func contacts() async throws -> [Contact] {
        cards.current
    }
}

struct FakeAPIError: Error {}

/// Records each upload. It fails the upload calls whose 1-based numbers are in `failingCalls`.
final class RecordingAPI: SyncAPI, @unchecked Sendable {
    struct ContactUpload: Equatable {
        var ids: [String]
        var deleted: [String]
    }

    let messageBatches = Locked<[[Int64]]>([])
    let contactUploads = Locked<[ContactUpload]>([])
    let failingMessageCalls: Locked<Set<Int>>
    let failingContactCalls: Locked<Set<Int>>
    private let messageCalls = Locked(0)
    private let contactCalls = Locked(0)

    init(failingMessageCalls: Set<Int> = [], failingContactCalls: Set<Int> = []) {
        self.failingMessageCalls = Locked(failingMessageCalls)
        self.failingContactCalls = Locked(failingContactCalls)
    }

    func upload(messages: [Message], deviceID: String) async throws {
        let call = messageCalls.withLock { calls -> Int in
            calls += 1
            return calls
        }
        if failingMessageCalls.current.contains(call) { throw FakeAPIError() }
        messageBatches.withLock { $0.append(messages.map(\.rowID)) }
    }

    func upload(contacts: [Contact], deletedContactIDs: [String], deviceID: String) async throws {
        let call = contactCalls.withLock { calls -> Int in
            calls += 1
            return calls
        }
        if failingContactCalls.current.contains(call) { throw FakeAPIError() }
        contactUploads.withLock { $0.append(ContactUpload(ids: contacts.map(\.id), deleted: deletedContactIDs)) }
    }
}

/// Returns queued results in order and records each request.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    let results: Locked<[Result<HTTPResponse, any Error>]>
    let requests = Locked<[URLRequest]>([])

    init(_ results: [Result<HTTPResponse, any Error>]) {
        self.results = Locked(results)
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.withLock { $0.append(request) }
        let next = results.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        guard let next else {
            XCTFail("The transport got more requests than the test expected.")
            return HTTPResponse(statusCode: 500)
        }
        return try next.get()
    }
}
