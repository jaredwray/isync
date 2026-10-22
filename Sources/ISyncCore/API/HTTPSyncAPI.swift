import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A JSON-over-HTTPS client for the sync API. `docs/API.md` describes the
/// contract. Change this type, or add a different `SyncAPI` conformer, when
/// the real API is ready.
public struct HTTPSyncAPI: SyncAPI {
    public static let messagesPath = "v1/messages"
    public static let contactsPath = "v1/contacts"

    public let baseURL: URL
    private let token: String?
    private let userAgent: String
    private let transport: any HTTPTransport
    private let retry: RetryPolicy

    /// - Parameter token: Sent as `Authorization: Bearer <token>`. Nil sends no header.
    public init(
        baseURL: URL,
        token: String?,
        userAgent: String = "isync/\(ISyncVersion.current)",
        transport: any HTTPTransport = URLSessionTransport(),
        retry: RetryPolicy = RetryPolicy()
    ) throws {
        try Self.validate(baseURL)
        self.baseURL = baseURL
        self.token = token.flatMap { $0.isEmpty ? nil : $0 }
        self.userAgent = userAgent
        self.transport = transport
        self.retry = retry
    }

    /// Permits HTTPS, and plain HTTP to a loopback host for local tests.
    public static func validate(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: false), !host.isEmpty else {
            throw SyncAPIError.insecureURL(url.absoluteString)
        }
        let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]
        guard scheme == "https" || (scheme == "http" && loopbackHosts.contains(host.lowercased())) else {
            throw SyncAPIError.insecureURL(url.absoluteString)
        }
    }

    public func upload(messages: [Message], deviceID: String) async throws {
        try await post(Self.messagesPath, body: MessagesRequest(deviceID: deviceID, messages: messages))
    }

    public func upload(contacts: [Contact], deletedContactIDs: [String], deviceID: String) async throws {
        try await post(
            Self.contactsPath,
            body: ContactsRequest(deviceID: deviceID, contacts: contacts, deletedContactIDs: deletedContactIDs)
        )
    }

    // MARK: - Request

    private struct MessagesRequest: Encodable {
        var deviceID: String
        var messages: [Message]
    }

    private struct ContactsRequest: Encodable {
        var deviceID: String
        var contacts: [Contact]
        var deletedContactIDs: [String]

        // The snake_case strategy turns "IDs" into "i_ds". This key gives "deleted_contact_ids".
        enum CodingKeys: String, CodingKey {
            case deviceID
            case contacts
            case deletedContactIDs = "deletedContactIds"
        }
    }

    private enum Outcome {
        case success
        case fail(SyncAPIError)
        case retry(SyncAPIError, retryAfter: Duration?)
    }

    private func post(_ path: String, body: some Encodable) async throws {
        let data = try JSONCoding.apiEncoder().encode(body)
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // The same body gives the same key, so the server can drop a repeated batch.
        request.setValue(FNV1a.hexDigest(data), forHTTPHeaderField: "Idempotency-Key")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        for attempt in 1...retry.maxAttempts {
            let outcome: Outcome
            do {
                outcome = Self.classify(try await transport.send(request))
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as SyncAPIError {
                outcome = .fail(error)
            } catch {
                outcome = .retry(.transport(error.localizedDescription), retryAfter: nil)
            }

            switch outcome {
            case .success:
                return
            case let .fail(error):
                throw error
            case let .retry(error, retryAfter):
                guard attempt < retry.maxAttempts else { throw error }
                Log.info("API attempt \(attempt) of \(retry.maxAttempts) failed. \(error)")
                try await retry.sleep(retry.delay(afterAttempt: attempt, retryAfter: retryAfter))
            }
        }
    }

    private static func classify(_ response: HTTPResponse) -> Outcome {
        let status = response.statusCode
        switch status {
        case 200..<300:
            return .success
        case 401, 403:
            return .fail(.unauthorized(status: status))
        case 408, 425, 429, 500..<600:
            let retryAfter = response.headers["retry-after"]
                .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .map { Duration.seconds(max(0, $0)) }
            return .retry(.unavailable(status: status), retryAfter: retryAfter)
        default:
            return .fail(.rejected(status: status, detail: detail(from: response.body)))
        }
    }

    /// The start of an error body, for the sync status. It is from our own server.
    private static func detail(from body: Data) -> String {
        let text = String(decoding: body.prefix(200), as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
