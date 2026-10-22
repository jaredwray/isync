import XCTest

@testable import ISyncCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class HTTPSyncAPITests: XCTestCase {
    private let baseURL = URL(string: "https://api.example.com/sync")!

    private func makeAPI(_ transport: FakeTransport, sleeps: Locked<[Duration]> = Locked([])) throws -> HTTPSyncAPI {
        try HTTPSyncAPI(
            baseURL: baseURL,
            token: "secret-token",
            transport: transport,
            retry: RetryPolicy(maxAttempts: 3, sleep: { duration in sleeps.withLock { $0.append(duration) } })
        )
    }

    func testMessageUploadSendsAuthenticatedSnakeCaseJSON() async throws {
        let transport = FakeTransport([.success(HTTPResponse(statusCode: 202))])
        let message = Message(
            rowID: 7,
            guid: "m7",
            text: "Hi",
            isFromMe: true,
            date: Date(timeIntervalSince1970: 1_767_225_600.25),
            associatedMessageGUID: "p:0/m6"
        )

        try await makeAPI(transport).upload(messages: [message], deviceID: "device-1")

        let request = try XCTUnwrap(transport.requests.current.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/sync/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "isync/\(ISyncVersion.current)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key")?.count, 16)

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["device_id"] as? String, "device-1")
        let sent = try XCTUnwrap((json["messages"] as? [[String: Any]])?.first)
        XCTAssertEqual(sent["row_id"] as? Int, 7)
        XCTAssertEqual(sent["is_from_me"] as? Bool, true)
        XCTAssertEqual(sent["associated_message_guid"] as? String, "p:0/m6")
        XCTAssertEqual(sent["date"] as? String, "2026-01-01T00:00:00.250Z")
    }

    func testContactUploadSendsCardsAndDeletedIDs() async throws {
        let transport = FakeTransport([.success(HTTPResponse(statusCode: 200))])

        try await makeAPI(transport).upload(
            contacts: [Contact(id: "c1", givenName: "Ana")],
            deletedContactIDs: ["c2"],
            deviceID: "device-1"
        )

        let request = try XCTUnwrap(transport.requests.current.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/sync/v1/contacts")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual((json["contacts"] as? [[String: Any]])?.first?["given_name"] as? String, "Ana")
        XCTAssertEqual(json["deleted_contact_ids"] as? [String], ["c2"])
    }

    func testRetriesServerFailuresWithTheSameIdempotencyKeyAndUsesRetryAfter() async throws {
        let transport = FakeTransport([
            .success(HTTPResponse(statusCode: 503, headers: ["Retry-After": "7"])),
            .failure(URLError(.networkConnectionLost)),
            .success(HTTPResponse(statusCode: 200)),
            .success(HTTPResponse(statusCode: 200)),
        ])
        let sleeps = Locked<[Duration]>([])
        let api = try makeAPI(transport, sleeps: sleeps)
        let batch = [Message(rowID: 1, guid: "m1", text: "Hi")]

        try await api.upload(messages: batch, deviceID: "d")
        try await api.upload(messages: batch, deviceID: "d")

        XCTAssertEqual(sleeps.current, [.seconds(7), .seconds(2)])
        let keys = transport.requests.current.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        XCTAssertEqual(keys.count, 4)
        XCTAssertEqual(Set(keys).count, 1, "a repeated batch must have the same key, so the server can drop it")
    }

    func testStopsAfterTheLastAttempt() async throws {
        let transport = FakeTransport(Array(repeating: .success(HTTPResponse(statusCode: 500)), count: 3))

        do {
            try await makeAPI(transport).upload(messages: [], deviceID: "d")
            XCTFail("The upload must fail.")
        } catch {
            XCTAssertEqual(error as? SyncAPIError, .unavailable(status: 500))
        }
        XCTAssertEqual(transport.requests.current.count, 3)
    }

    func testDoesNotRetryAClientError() async throws {
        let cases: [(HTTPResponse, SyncAPIError)] = [
            (
                HTTPResponse(statusCode: 400, body: Data(" bad field \n".utf8)),
                .rejected(status: 400, detail: "bad field")
            ),
            (HTTPResponse(statusCode: 401), .unauthorized(status: 401)),
            (HTTPResponse(statusCode: 302), .rejected(status: 302, detail: "")),
        ]
        for (response, expected) in cases {
            let transport = FakeTransport([.success(response)])
            do {
                try await makeAPI(transport).upload(messages: [], deviceID: "d")
                XCTFail("HTTP \(response.statusCode) must fail.")
            } catch {
                XCTAssertEqual(error as? SyncAPIError, expected)
            }
            XCTAssertEqual(transport.requests.current.count, 1, "HTTP \(response.statusCode)")
        }
    }

    func testPermitsPlainHTTPOnlyForLoopbackHosts() {
        let cases: [(String, Bool)] = [
            ("https://api.example.com", true),
            ("http://localhost:8080", true),
            ("http://127.0.0.1:8080", true),
            ("http://[::1]:8080", true),
            ("http://api.example.com", false),
            ("ftp://api.example.com", false),
            ("https://", false),
        ]
        for (string, permitted) in cases {
            let url = URL(string: string)!
            if permitted {
                XCTAssertNoThrow(try HTTPSyncAPI.validate(url), string)
            } else {
                XCTAssertThrowsError(try HTTPSyncAPI.validate(url), string)
            }
        }
    }
}
