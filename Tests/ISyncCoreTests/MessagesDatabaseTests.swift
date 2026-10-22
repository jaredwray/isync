import XCTest

@testable import ISyncCore

final class MessagesDatabaseTests: XCTestCase {
    /// 2026-01-02T03:04:05.5Z as nanoseconds since 2001-01-01.
    private let nanoseconds: Int64 = 788_929_445_500_000_000

    func testReadsOnlyRowsAfterTheCursorInRowIDOrderUpToTheLimit() throws {
        let fixture = try ChatDatabaseFixture()
        try fixture.execute(
            """
            INSERT INTO message (guid, text) VALUES ('a', 'one'), ('b', 'two'), ('c', 'three');
            """)
        let database = MessagesDatabase(url: fixture.url)

        XCTAssertEqual(try database.messages(after: 1, limit: 1).map(\.guid), ["b"])
        XCTAssertEqual(try database.messages(after: 0, limit: 10).map(\.rowID), [1, 2, 3])
        XCTAssertEqual(try database.messages(after: 3, limit: 10), [])
    }

    func testMapsChatParticipantsAttachmentsAndDates() throws {
        let fixture = try ChatDatabaseFixture()
        try fixture.execute(
            """
            INSERT INTO handle (id, service) VALUES ('+15550000001', 'iMessage'), ('friend@example.com', 'iMessage');
            INSERT INTO chat (guid, style, chat_identifier, service_name, display_name)
                VALUES ('iMessage;+;chat1', 43, 'chat1', 'iMessage', 'Team');
            INSERT INTO chat_handle_join VALUES (1, 2), (1, 1);
            INSERT INTO message (guid, text, handle_id, service, date, date_read, date_delivered, is_from_me,
                associated_message_guid, associated_message_type, thread_originator_guid, date_edited)
                VALUES ('m1', 'Lunch?', 1, 'iMessage', \(nanoseconds), 788929445, 0, 0, 'p:0/m0', 2001, 'm0', 0);
            INSERT INTO chat_message_join VALUES (1, 1);
            INSERT INTO attachment (guid, filename, mime_type, transfer_name, total_bytes)
                VALUES ('a1', '~/Library/Messages/Attachments/x/photo.heic', 'image/heic', 'photo.heic', 2048);
            INSERT INTO message_attachment_join VALUES (1, 1);
            """)

        let message = try XCTUnwrap(MessagesDatabase(url: fixture.url).messages(after: 0, limit: 10).first)

        XCTAssertEqual(message.text, "Lunch?")
        XCTAssertEqual(message.handle, "+15550000001")
        XCTAssertFalse(message.isFromMe)
        XCTAssertEqual(try XCTUnwrap(message.date).timeIntervalSinceReferenceDate, 788_929_445.5, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(message.dateRead).timeIntervalSinceReferenceDate, 788_929_445, accuracy: 1e-6)
        XCTAssertNil(message.dateDelivered, "0 means no date")
        XCTAssertNil(message.dateEdited)
        XCTAssertEqual(message.associatedMessageGUID, "p:0/m0")
        XCTAssertEqual(message.associatedMessageType, 2001)
        XCTAssertEqual(message.threadOriginatorGUID, "m0")
        XCTAssertEqual(
            message.chat,
            Chat(
                guid: "iMessage;+;chat1",
                identifier: "chat1",
                displayName: "Team",
                service: "iMessage",
                isGroup: true,
                participants: ["+15550000001", "friend@example.com"]
            ))
        XCTAssertEqual(
            message.attachments,
            [
                Attachment(
                    guid: "a1",
                    filename: "~/Library/Messages/Attachments/x/photo.heic",
                    mimeType: "image/heic",
                    transferName: "photo.heic",
                    totalBytes: 2048
                )
            ])
    }

    func testUsesAttributedBodyWhenTheTextColumnIsEmptyAndKeepsBodiesThatItCannotRead() throws {
        let fixture = try ChatDatabaseFixture()
        let unreadable = Data("streamtyped, but not a string record".utf8)
        try fixture.execute(
            """
            INSERT INTO message (guid, text, attributedBody) VALUES
                ('null-text', NULL, \(attributedBody("From the body").hexLiteral)),
                ('empty-text', '', \(attributedBody("Also from the body").hexLiteral)),
                ('both', 'From the column', \(attributedBody("Ignored").hexLiteral)),
                ('unreadable', NULL, \(unreadable.hexLiteral));
            """)

        let messages = try MessagesDatabase(url: fixture.url).messages(after: 0, limit: 10)

        XCTAssertEqual(messages.map(\.text), ["From the body", "Also from the body", "From the column", nil])
        XCTAssertEqual(messages.map(\.attributedBody), [nil, nil, nil, unreadable])
    }

    func testReadsAnOlderSchemaWithoutTheOptionalColumns() throws {
        let fixture = try ChatDatabaseFixture(includeOptionalColumns: false)
        try fixture.execute("INSERT INTO message (guid, text, date) VALUES ('old', 'Hi', 500000000);")

        let message = try XCTUnwrap(MessagesDatabase(url: fixture.url).messages(after: 0, limit: 10).first)

        XCTAssertEqual(message.text, "Hi")
        XCTAssertEqual(message.date, Date(timeIntervalSinceReferenceDate: 500_000_000))
        XCTAssertNil(message.associatedMessageGUID)
        XCTAssertNil(message.chat)
    }

    func testLatestRowIDDoesNotGoDownWhenTheNewestRowsAreDeleted() throws {
        let fixture = try ChatDatabaseFixture()
        try fixture.execute(
            """
            INSERT INTO message (guid) VALUES ('a'), ('b'), ('c');
            DELETE FROM message WHERE ROWID = 3;
            """)

        XCTAssertEqual(try MessagesDatabase(url: fixture.url).latestRowID(), 3)
    }

    func testAMissingDatabaseIsNotFound() throws {
        let url = try temporaryDirectory().appending(path: "chat.db")

        XCTAssertThrowsError(try MessagesDatabase(url: url).latestRowID()) { error in
            XCTAssertEqual(error as? MessagesDatabaseError, .notFound(path: url.path(percentEncoded: false)))
        }
    }
}
