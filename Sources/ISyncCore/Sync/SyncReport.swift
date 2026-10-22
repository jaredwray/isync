import Foundation

/// The result of one sync run.
public struct SyncReport: Equatable, Sendable {
    public var startedAt: Date
    public var finishedAt: Date
    public var messagesUploaded = 0
    /// Uploaded messages whose text the decoder could not read. They carry the raw body.
    /// A value above 0 after a macOS update can mean that the body format changed.
    public var messagesWithRawBody = 0
    public var contactsUploaded = 0
    public var contactsDeleted = 0
    public var failures: [SyncFailure] = []
    /// True when the engine did not run because a different run was in progress.
    public var skipped = false

    public var succeeded: Bool { !skipped && failures.isEmpty }

    public init(startedAt: Date, finishedAt: Date? = nil) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt ?? startedAt
    }
}

/// A part of the sync that failed. The reason holds no message or contact data.
public struct SyncFailure: Equatable, Sendable, CustomStringConvertible {
    public enum Part: String, Sendable {
        case state
        case messages
        case contacts
    }

    public var part: Part
    public var reason: String

    public init(part: Part, reason: String) {
        self.part = part
        self.reason = reason
    }

    public var description: String { "\(part.rawValue): \(reason)" }
}
