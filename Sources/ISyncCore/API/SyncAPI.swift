import Foundation

/// The remote API that gets the synced data.
///
/// The sync calls a method again with the same data when an earlier call
/// failed, so a conformer must accept repeated data. Use `Message.guid` and
/// `Contact.id` as the keys.
public protocol SyncAPI: Sendable {
    func upload(messages: [Message], deviceID: String) async throws
    func upload(contacts: [Contact], deletedContactIDs: [String], deviceID: String) async throws
}

public enum SyncAPIError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The URL is not HTTPS. Plain HTTP is permitted only for a loopback host.
    case insecureURL(String)
    case unauthorized(status: Int)
    /// The server refused the request. Do not send the same request again.
    case rejected(status: Int, detail: String)
    /// The server failed on each attempt.
    case unavailable(status: Int)
    case transport(String)
    case invalidResponse

    public var description: String {
        switch self {
        case let .insecureURL(url):
            "The API URL \(url) is not HTTPS. Plain HTTP is permitted only for localhost."
        case let .unauthorized(status):
            "The API refused the token (HTTP \(status))."
        case let .rejected(status, detail):
            detail.isEmpty
                ? "The API refused the request (HTTP \(status))."
                : "The API refused the request (HTTP \(status)): \(detail)"
        case let .unavailable(status):
            "The API is not available (HTTP \(status))."
        case let .transport(reason):
            "Cannot connect to the API: \(reason)"
        case .invalidResponse:
            "The API sent a response that is not HTTP."
        }
    }
}
