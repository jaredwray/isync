import Foundation
import XCTest

@testable import ISyncMac

final class FileLockTests: XCTestCase {
    /// The app and isync-cli write the same state file. Only one of them can hold the sync lock.
    func testASecondHolderCannotTakeTheSyncLock() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "isync-lock-\(UUID().uuidString)")
            .appending(path: "sync.lock")
        let first = try XCTUnwrap(try FileLock(url: url))

        XCTAssertNil(try FileLock(url: url), "a second holder is refused")
        first.unlock()
        XCTAssertNotNil(try FileLock(url: url), "the lock is free after unlock")
    }
}
