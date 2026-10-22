import Foundation

/// One row of the Messages database, in the shape that the API gets.
public struct Message: Codable, Equatable, Sendable {
    /// The ROWID in chat.db. The sync cursor uses it. It is unique on one Mac only.
    public var rowID: Int64
    /// The message GUID. It is stable across devices. Use it as the idempotency key.
    public var guid: String
    public var text: String?
    /// The raw `attributedBody` bytes. Set only when the `text` column is empty and the
    /// decoder cannot read the body, so that the server keeps the content. JSON sends it as Base64.
    public var attributedBody: Data?
    /// "iMessage", "SMS", or "RCS".
    public var service: String?
    public var isFromMe: Bool
    /// The phone number or email address of the other person, if known.
    public var handle: String?
    public var date: Date?
    public var dateRead: Date?
    public var dateDelivered: Date?
    public var dateEdited: Date?
    public var dateRetracted: Date?
    /// 0 for a normal message. Other values are group events, such as a new group name.
    public var itemType: Int
    /// The GUID of the message that this tapback or reply refers to.
    public var associatedMessageGUID: String?
    /// 0 for a normal message. 2000...2005 add a tapback. 3000...3005 remove a tapback.
    public var associatedMessageType: Int
    /// The GUID of the first message of an inline reply thread.
    public var threadOriginatorGUID: String?
    public var chat: Chat?
    public var attachments: [Attachment]

    public init(
        rowID: Int64,
        guid: String,
        text: String? = nil,
        attributedBody: Data? = nil,
        service: String? = nil,
        isFromMe: Bool = false,
        handle: String? = nil,
        date: Date? = nil,
        dateRead: Date? = nil,
        dateDelivered: Date? = nil,
        dateEdited: Date? = nil,
        dateRetracted: Date? = nil,
        itemType: Int = 0,
        associatedMessageGUID: String? = nil,
        associatedMessageType: Int = 0,
        threadOriginatorGUID: String? = nil,
        chat: Chat? = nil,
        attachments: [Attachment] = []
    ) {
        self.rowID = rowID
        self.guid = guid
        self.text = text
        self.attributedBody = attributedBody
        self.service = service
        self.isFromMe = isFromMe
        self.handle = handle
        self.date = date
        self.dateRead = dateRead
        self.dateDelivered = dateDelivered
        self.dateEdited = dateEdited
        self.dateRetracted = dateRetracted
        self.itemType = itemType
        self.associatedMessageGUID = associatedMessageGUID
        self.associatedMessageType = associatedMessageType
        self.threadOriginatorGUID = threadOriginatorGUID
        self.chat = chat
        self.attachments = attachments
    }
}

/// The conversation that a message is in.
public struct Chat: Codable, Equatable, Sendable {
    public var guid: String
    public var identifier: String?
    public var displayName: String?
    public var service: String?
    public var isGroup: Bool
    /// The phone numbers and email addresses of the other people in the chat.
    public var participants: [String]

    public init(
        guid: String,
        identifier: String? = nil,
        displayName: String? = nil,
        service: String? = nil,
        isGroup: Bool = false,
        participants: [String] = []
    ) {
        self.guid = guid
        self.identifier = identifier
        self.displayName = displayName
        self.service = service
        self.isGroup = isGroup
        self.participants = participants
    }
}

/// Attachment metadata. The sync does not upload attachment files.
public struct Attachment: Codable, Equatable, Sendable {
    public var guid: String
    public var filename: String?
    public var mimeType: String?
    public var transferName: String?
    public var totalBytes: Int64?

    public init(
        guid: String,
        filename: String? = nil,
        mimeType: String? = nil,
        transferName: String? = nil,
        totalBytes: Int64? = nil
    ) {
        self.guid = guid
        self.filename = filename
        self.mimeType = mimeType
        self.transferName = transferName
        self.totalBytes = totalBytes
    }
}
