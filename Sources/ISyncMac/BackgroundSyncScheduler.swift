import Foundation

/// Runs the sync on a repeating schedule with `NSBackgroundActivityScheduler`.
/// macOS picks the exact time inside the tolerance, so the work runs when the
/// Mac is not busy and does not wake it from sleep.
@MainActor
public final class BackgroundSyncScheduler {
    private let identifier: String
    private let work: @Sendable () async -> Bool
    private var scheduler: NSBackgroundActivityScheduler?

    /// - Parameter work: Returns false when it did not run, for example because a sync is in progress.
    ///   The scheduler then asks macOS to run it again soon, not after a full interval.
    public init(identifier: String = "com.jaredwray.isync.sync", work: @escaping @Sendable () async -> Bool) {
        self.identifier = identifier
        self.work = work
    }

    /// Starts the schedule, or starts it again with a new interval.
    public func start(intervalMinutes: Int) {
        stop()
        let scheduler = NSBackgroundActivityScheduler(identifier: identifier)
        scheduler.repeats = true
        scheduler.interval = TimeInterval(intervalMinutes * 60)
        scheduler.tolerance = scheduler.interval / 4
        scheduler.qualityOfService = .utility
        let work = work
        // The scheduler calls this block on a background queue, so the block must not be main-actor isolated.
        scheduler.schedule { @Sendable completion in
            let done = UncheckedSendable(completion)
            Task {
                let ran = await work()
                done.value(ran ? .finished : .deferred)
            }
        }
        self.scheduler = scheduler
    }

    public func stop() {
        scheduler?.invalidate()
        scheduler = nil
    }
}

/// Moves a completion handler across tasks. The scheduler calls the handler once.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
