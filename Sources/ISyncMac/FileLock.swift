import Darwin
import Foundation

/// An advisory lock on a file. One holder at a time can have it, also across processes.
/// The system releases the lock when the process stops, so a crash does not leave a stale lock.
final class FileLock {
    private var descriptor: Int32

    /// Returns nil when a different holder has the lock.
    init?(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let opened = open(url.path(percentEncoded: false), O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard opened >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(opened)
            if code == EAGAIN { return nil }  // EAGAIN is EWOULDBLOCK on Darwin.
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        descriptor = opened
    }

    func unlock() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        unlock()
    }
}
