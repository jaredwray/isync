import Foundation

/// What the sync sent so far. The sync saves it after each successful upload.
public struct SyncState: Codable, Equatable, Sendable {
    /// A random ID for this Mac. The API uses it to tell devices apart.
    public var deviceID: String
    /// The highest chat.db ROWID that the API accepted.
    public var messageCursor: Int64
    /// The content hash of each contact that the API accepted, by contact ID.
    public var contactHashes: [String: String]
    public var lastMessageSync: Date?
    public var lastContactSync: Date?

    public init(
        deviceID: String = UUID().uuidString,
        messageCursor: Int64 = 0,
        contactHashes: [String: String] = [:],
        lastMessageSync: Date? = nil,
        lastContactSync: Date? = nil
    ) {
        self.deviceID = deviceID
        self.messageCursor = messageCursor
        self.contactHashes = contactHashes
        self.lastMessageSync = lastMessageSync
        self.lastContactSync = lastContactSync
    }
}

public protocol SyncStateStore: Sendable {
    /// The saved state. If there is no saved state, this makes a new state with
    /// a new device ID, saves it, and returns it.
    func load() throws -> SyncState
    func save(_ state: SyncState) throws
}

/// Keeps the state in a JSON file that only the current user can read.
public struct FileSyncStateStore: SyncStateStore {
    public let url: URL

    public init(url: URL = AppPaths.stateFile) {
        self.url = url
    }

    public func load() throws -> SyncState {
        if let state = try loadIfPresent() { return state }
        let state = SyncState()
        try save(state)
        return state
    }

    /// The saved state, or nil if there is no file. This does not write a file.
    public func loadIfPresent() throws -> SyncState? {
        guard PrivateFile.exists(url) else { return nil }
        return try JSONCoding.storageDecoder().decode(SyncState.self, from: Data(contentsOf: url))
    }

    public func save(_ state: SyncState) throws {
        try PrivateFile.write(JSONCoding.storageEncoder().encode(state), to: url)
    }
}

/// An in-memory store for tests and dry runs.
public final class InMemorySyncStateStore: SyncStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: SyncState

    public init(_ state: SyncState = SyncState()) {
        self.state = state
    }

    public func load() throws -> SyncState {
        lock.withLock { state }
    }

    public func save(_ state: SyncState) throws {
        lock.withLock { self.state = state }
    }
}
