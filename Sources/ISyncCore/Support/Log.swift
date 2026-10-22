import Foundation

#if canImport(os)
    import os
#endif

/// The app log. Callers must not put message text, contact details, or tokens in a log entry.
/// Log entries hold counts, cursors, status codes, and error descriptions only.
public enum Log {
    #if canImport(os)
        private static let logger = Logger(subsystem: "com.jaredwray.isync", category: "sync")
    #endif

    public static func info(_ entry: String) {
        #if canImport(os)
            logger.info("\(entry, privacy: .public)")
        #else
            FileHandle.standardError.write(Data("[isync] \(entry)\n".utf8))
        #endif
    }

    public static func error(_ entry: String) {
        #if canImport(os)
            logger.error("\(entry, privacy: .public)")
        #else
            FileHandle.standardError.write(Data("[isync] error: \(entry)\n".utf8))
        #endif
    }
}
