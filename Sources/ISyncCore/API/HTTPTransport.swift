import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct HTTPResponse: Sendable, Equatable {
    public var statusCode: Int
    /// Header names are lowercase.
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        self.body = body
    }
}

/// Sends one HTTP request. Tests use a fake transport.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// A transport on an ephemeral `URLSession`. It keeps no cookies and no cache
/// on disk, and it does not follow redirects. A redirect could send the token
/// and private data to a different host.
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    // URLSession is thread-safe, and this class does not change it after init.
    private let session: URLSession

    /// - Parameters:
    ///   - timeout: The longest wait for more response data.
    ///   - resourceTimeout: The longest time for one request. A slow server cannot block the sync for longer.
    public init(timeout: TimeInterval = 60, resourceTimeout: TimeInterval = 600) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncAPIError.invalidResponse }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}

/// Stops each redirect. The caller then gets the 3xx response.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    #if canImport(FoundationNetworking)
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    #else
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    #endif
}
