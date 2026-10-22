import XCTest

@testable import ISyncCore

final class StorageTests: XCTestCase {
    func testStateStoreKeepsOneDeviceIDAndWritesPrivateFiles() throws {
        let url = try temporaryDirectory().appending(path: "isync/state.json")
        let store = FileSyncStateStore(url: url)

        var state = try store.load()
        state.messageCursor = 42
        try store.save(state)
        let reloaded = try FileSyncStateStore(url: url).load()

        XCTAssertEqual(reloaded, state)
        let manager = FileManager.default
        let fileMode = try manager.attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions]
        let directoryPath = url.deletingLastPathComponent().path(percentEncoded: false)
        let directoryMode = try manager.attributesOfItem(atPath: directoryPath)[.posixPermissions]
        XCTAssertEqual((fileMode as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((directoryMode as? NSNumber)?.intValue, 0o700)
    }

    func testConfigurationFromAnOlderFileGetsDefaultsForOmittedKeys() throws {
        let json = Data(#"{"apiBaseURL": "https://api.example.com", "syncContacts": false}"#.utf8)

        let configuration = try JSONCoding.storageDecoder().decode(SyncConfiguration.self, from: json)

        var expected = SyncConfiguration(apiBaseURL: URL(string: "https://api.example.com"))
        expected.syncContacts = false
        XCTAssertEqual(configuration, expected)
    }

    func testConfigurationStoreRejectsAnInvalidConfiguration() throws {
        let url = try temporaryDirectory().appending(path: "config.json")
        let store = ConfigurationStore(url: url)
        let invalid: [(SyncConfiguration, String)] = [
            (SyncConfiguration(syncIntervalMinutes: 1), "interval below the minimum"),
            (SyncConfiguration(messageBatchSize: 0), "batch size of 0"),
            (SyncConfiguration(apiBaseURL: URL(string: "http://api.example.com")), "plain HTTP to a remote host"),
        ]
        for (configuration, name) in invalid {
            XCTAssertThrowsError(try store.save(configuration), name)
        }
        XCTAssertEqual(try store.load(), SyncConfiguration(), "nothing was saved")

        // A person can edit the file. The sync engine must not get a batch size of 0.
        try Data(#"{"messageBatchSize": 0}"#.utf8).write(to: url)
        XCTAssertThrowsError(try store.load())
    }
}
