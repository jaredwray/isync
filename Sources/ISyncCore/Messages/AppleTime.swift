import Foundation

/// Converts chat.db timestamps to `Date`.
enum AppleTime {
    /// Values above this limit are nanoseconds. Lower values are seconds.
    /// macOS 10.13 and later write nanoseconds. Older versions wrote seconds.
    private static let nanosecondLimit: Int64 = 1_000_000_000_000

    /// Converts a value that counts from 2001-01-01 00:00:00 UTC.
    /// Returns nil for 0, which chat.db uses for "no date".
    static func date(fromMessagesTimestamp value: Int64?) -> Date? {
        guard let value, value != 0 else { return nil }
        let seconds =
            value.magnitude > UInt64(nanosecondLimit)
            ? Double(value) / 1_000_000_000
            : Double(value)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }
}
