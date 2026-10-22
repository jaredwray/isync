import Foundation

/// When to send a failed request again.
public struct RetryPolicy: Sendable {
    /// The total number of attempts, including the first one.
    public var maxAttempts: Int
    public var baseDelay: Duration
    public var maxDelay: Duration
    /// Waits between attempts. Tests replace it so that they do not wait.
    public var sleep: @Sendable (Duration) async throws -> Void

    public init(
        maxAttempts: Int = 4,
        baseDelay: Duration = .seconds(1),
        maxDelay: Duration = .seconds(60),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        precondition(maxAttempts >= 1, "maxAttempts must be 1 or more")
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.sleep = sleep
    }

    /// The wait after failed attempt number `attempt` (1-based). A server
    /// `Retry-After` value comes first. Both values stop at `maxDelay`.
    func delay(afterAttempt attempt: Int, retryAfter: Duration?) -> Duration {
        if let retryAfter { return min(retryAfter, maxDelay) }
        let factor = 1 << min(attempt - 1, 16)
        return min(baseDelay * factor, maxDelay)
    }
}
