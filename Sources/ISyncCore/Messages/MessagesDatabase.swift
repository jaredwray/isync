import Foundation

/// A read-only source of messages.
public protocol MessageSource: Sendable {
    /// The highest message ROWID that the database issued. It does not go down
    /// when a person deletes messages. It goes down when the database is new.
    func latestRowID() throws -> Int64

    /// Up to `limit` messages with a ROWID above `cursor`, in ROWID order.
    func messages(after cursor: Int64, limit: Int) throws -> [Message]
}

public enum MessagesDatabaseError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFound(path: String)
    /// macOS blocks access to ~/Library/Messages for apps without Full Disk Access.
    case accessDenied(path: String)
    case unreadable(path: String, reason: String)

    public var description: String {
        switch self {
        case let .notFound(path):
            "No Messages database at \(path)."
        case let .accessDenied(path):
            "Cannot read \(path). Give isync Full Disk Access in System Settings > Privacy & Security."
        case let .unreadable(path, reason):
            "Cannot read \(path): \(reason)"
        }
    }
}

/// Reads `~/Library/Messages/chat.db`. Each call opens a new read-only
/// connection and closes it before it returns, so the sync never holds a lock
/// on the database between runs.
public struct MessagesDatabase: MessageSource {
    public let url: URL

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Messages/chat.db", directoryHint: .notDirectory)
    }

    public init(url: URL = MessagesDatabase.defaultURL) {
        self.url = url
    }

    /// Columns that older macOS versions do not have. The query selects NULL in their place.
    static let optionalMessageColumns: [String] = [
        "attributedBody",
        "date_edited",
        "date_retracted",
        "associated_message_guid",
        "associated_message_type",
        "thread_originator_guid",
    ]

    public func latestRowID() throws -> Int64 {
        try withDatabase { database in
            var latest: Int64 = 0
            let maximum = try database.prepare("SELECT IFNULL(MAX(ROWID), 0) FROM message")
            if try maximum.step() { latest = maximum.int64(at: 0) }

            // chat.db declares message.ROWID with AUTOINCREMENT, so sqlite_sequence
            // keeps the highest ROWID even after the newest rows are deleted.
            if try !database.columnNames(of: "sqlite_sequence").isEmpty {
                let sequence = try database.prepare("SELECT seq FROM sqlite_sequence WHERE name = 'message'")
                if try sequence.step() { latest = max(latest, sequence.int64(at: 0)) }
            }
            return latest
        }
    }

    public func messages(after cursor: Int64, limit: Int) throws -> [Message] {
        precondition(limit > 0, "limit must be positive")
        return try withDatabase { database in
            let available = try database.columnNames(of: "message")
            let optional = Self.optionalMessageColumns.map { available.contains($0) ? "m.\($0)" : "NULL" }
            let sql = """
                SELECT m.ROWID, m.guid, m.text, m.service, m.is_from_me, m.date, m.date_read,
                       m.date_delivered, m.item_type, \(optional.joined(separator: ", ")),
                       h.id, c.ROWID, c.guid, c.chat_identifier, c.display_name, c.service_name, c.style
                FROM message AS m
                LEFT JOIN handle AS h ON h.ROWID = m.handle_id
                LEFT JOIN chat AS c ON c.ROWID = (
                    SELECT cmj.chat_id FROM chat_message_join AS cmj
                    WHERE cmj.message_id = m.ROWID
                    ORDER BY cmj.chat_id
                    LIMIT 1
                )
                WHERE m.ROWID > ?1
                ORDER BY m.ROWID
                LIMIT ?2
                """
            let statement = try database.prepare(sql)
            try statement.bind([cursor, Int64(limit)])

            var rows: [(message: Message, chatRowID: Int64?)] = []
            while try statement.step() {
                rows.append(Self.message(from: statement))
            }

            let chatRowIDs = Set(rows.compactMap(\.chatRowID))
            let participants = try Self.participants(ofChats: chatRowIDs, in: database)
            let attachments = try Self.attachments(ofMessages: rows.map(\.message.rowID), in: database)
            let undecoded = rows.filter { $0.message.attributedBody != nil }.count
            if undecoded > 0 {
                Log.error("The decoder cannot read \(undecoded) message bodies. The raw bodies go to the API.")
            }

            return rows.map { row in
                var message = row.message
                if let chatRowID = row.chatRowID {
                    message.chat?.participants = participants[chatRowID] ?? []
                }
                message.attachments = attachments[message.rowID] ?? []
                return message
            }
        }
    }

    // MARK: - Row mapping

    /// chat.style is 43 for a group chat and 45 for a chat with one person.
    private static let groupChatStyle: Int64 = 43

    /// The column indexes follow the SELECT list in `messages(after:limit:)`.
    /// Index 9...14 are `optionalMessageColumns`, in that order.
    private static func message(from row: SQLiteStatement) -> (message: Message, chatRowID: Int64?) {
        let columnText = row.string(at: 2).flatMap { $0.isEmpty ? nil : $0 }
        let body = row.data(at: 9).flatMap { $0.isEmpty ? nil : $0 }
        let decodedText = columnText == nil ? body.flatMap(AttributedBodyDecoder.text(from:)) : nil
        let text = columnText ?? decodedText

        var chat: Chat?
        let chatRowID = row.optionalInt64(at: 16)
        if chatRowID != nil, let chatGUID = row.string(at: 17) {
            chat = Chat(
                guid: chatGUID,
                identifier: row.string(at: 18),
                displayName: row.string(at: 19).flatMap { $0.isEmpty ? nil : $0 },
                service: row.string(at: 20),
                isGroup: row.optionalInt64(at: 21) == groupChatStyle
            )
        }

        let message = Message(
            rowID: row.int64(at: 0),
            guid: row.string(at: 1) ?? "",
            text: text,
            attributedBody: text == nil ? body : nil,
            service: row.string(at: 3),
            isFromMe: row.int64(at: 4) != 0,
            handle: row.string(at: 15),
            date: AppleTime.date(fromMessagesTimestamp: row.optionalInt64(at: 5)),
            dateRead: AppleTime.date(fromMessagesTimestamp: row.optionalInt64(at: 6)),
            dateDelivered: AppleTime.date(fromMessagesTimestamp: row.optionalInt64(at: 7)),
            dateEdited: AppleTime.date(fromMessagesTimestamp: row.optionalInt64(at: 10)),
            dateRetracted: AppleTime.date(fromMessagesTimestamp: row.optionalInt64(at: 11)),
            itemType: Int(row.int64(at: 8)),
            associatedMessageGUID: row.string(at: 12),
            associatedMessageType: Int(row.int64(at: 13)),
            threadOriginatorGUID: row.string(at: 14),
            chat: chat
        )
        return (message, chat == nil ? nil : chatRowID)
    }

    private static func participants(
        ofChats chatRowIDs: Set<Int64>,
        in database: SQLiteDatabase
    ) throws -> [Int64: [String]] {
        guard !chatRowIDs.isEmpty else { return [:] }
        let ids = chatRowIDs.sorted()
        let statement = try database.prepare(
            """
            SELECT chj.chat_id, h.id
            FROM chat_handle_join AS chj
            JOIN handle AS h ON h.ROWID = chj.handle_id
            WHERE chj.chat_id IN (\(placeholders(ids.count)))
            ORDER BY chj.chat_id, h.id
            """)
        try statement.bind(ids)
        var result: [Int64: [String]] = [:]
        while try statement.step() {
            if let handle = statement.string(at: 1) {
                result[statement.int64(at: 0), default: []].append(handle)
            }
        }
        return result
    }

    private static func attachments(
        ofMessages messageRowIDs: [Int64],
        in database: SQLiteDatabase
    ) throws -> [Int64: [Attachment]] {
        guard !messageRowIDs.isEmpty else { return [:] }
        let statement = try database.prepare(
            """
            SELECT maj.message_id, a.guid, a.filename, a.mime_type, a.transfer_name, a.total_bytes
            FROM message_attachment_join AS maj
            JOIN attachment AS a ON a.ROWID = maj.attachment_id
            WHERE maj.message_id IN (\(placeholders(messageRowIDs.count)))
            ORDER BY maj.message_id, a.ROWID
            """)
        try statement.bind(messageRowIDs)
        var result: [Int64: [Attachment]] = [:]
        while try statement.step() {
            guard let guid = statement.string(at: 1) else { continue }
            let attachment = Attachment(
                guid: guid,
                filename: statement.string(at: 2),
                mimeType: statement.string(at: 3),
                transferName: statement.string(at: 4),
                totalBytes: statement.optionalInt64(at: 5)
            )
            result[statement.int64(at: 0), default: []].append(attachment)
        }
        return result
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    // MARK: - Connection

    private func withDatabase<T>(_ body: (SQLiteDatabase) throws -> T) throws -> T {
        let path = url.path(percentEncoded: false)
        let database: SQLiteDatabase
        do {
            database = try SQLiteDatabase(path: path, readOnly: true)
        } catch let error as SQLiteError {
            throw classifyOpenFailure(error, path: path)
        }
        do {
            return try body(database)
        } catch let error as SQLiteError {
            throw MessagesDatabaseError.unreadable(path: path, reason: error.description)
        }
    }

    /// SQLite reports most open failures as SQLITE_CANTOPEN. Look at the
    /// directory to tell a missing file from a privacy block.
    private func classifyOpenFailure(_ error: SQLiteError, path: String) -> MessagesDatabaseError {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent().path(percentEncoded: false)
        guard manager.fileExists(atPath: directory) else { return .notFound(path: path) }
        guard let entries = try? manager.contentsOfDirectory(atPath: directory) else {
            return .accessDenied(path: path)
        }
        guard entries.contains(url.lastPathComponent) else { return .notFound(path: path) }
        return .unreadable(path: path, reason: error.description)
    }
}
