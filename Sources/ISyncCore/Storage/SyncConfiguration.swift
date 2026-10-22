import Foundation

/// The settings that a person can change.
public struct SyncConfiguration: Codable, Equatable, Sendable {
    public static let intervalRange = 5...1_440
    public static let batchSizeRange = 1...5_000

    /// The API base URL. The sync does not run until a person sets it.
    public var apiBaseURL: URL?
    public var syncIntervalMinutes: Int
    public var syncMessages: Bool
    public var syncContacts: Bool
    public var messageBatchSize: Int
    public var contactBatchSize: Int

    public init(
        apiBaseURL: URL? = nil,
        syncIntervalMinutes: Int = 15,
        syncMessages: Bool = true,
        syncContacts: Bool = true,
        messageBatchSize: Int = 500,
        contactBatchSize: Int = 200
    ) {
        self.apiBaseURL = apiBaseURL
        self.syncIntervalMinutes = syncIntervalMinutes
        self.syncMessages = syncMessages
        self.syncContacts = syncContacts
        self.messageBatchSize = messageBatchSize
        self.contactBatchSize = contactBatchSize
    }

    /// A file from an older version can omit keys. Each omitted key gets its default value.
    public init(from decoder: any Decoder) throws {
        let defaults = SyncConfiguration()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiBaseURL = try container.decodeIfPresent(URL.self, forKey: .apiBaseURL)
        syncIntervalMinutes =
            try container.decodeIfPresent(Int.self, forKey: .syncIntervalMinutes)
            ?? defaults.syncIntervalMinutes
        syncMessages = try container.decodeIfPresent(Bool.self, forKey: .syncMessages) ?? defaults.syncMessages
        syncContacts = try container.decodeIfPresent(Bool.self, forKey: .syncContacts) ?? defaults.syncContacts
        messageBatchSize =
            try container.decodeIfPresent(Int.self, forKey: .messageBatchSize)
            ?? defaults.messageBatchSize
        contactBatchSize =
            try container.decodeIfPresent(Int.self, forKey: .contactBatchSize)
            ?? defaults.contactBatchSize
    }

    public enum ValidationError: Error, Equatable, Sendable, CustomStringConvertible {
        case intervalOutOfRange(Int)
        case batchSizeOutOfRange(Int)

        public var description: String {
            switch self {
            case let .intervalOutOfRange(value):
                "The sync interval must be \(SyncConfiguration.intervalRange.lowerBound) to "
                    + "\(SyncConfiguration.intervalRange.upperBound) minutes, not \(value)."
            case let .batchSizeOutOfRange(value):
                "A batch size must be \(SyncConfiguration.batchSizeRange.lowerBound) to "
                    + "\(SyncConfiguration.batchSizeRange.upperBound), not \(value)."
            }
        }
    }

    public func validate() throws {
        guard Self.intervalRange.contains(syncIntervalMinutes) else {
            throw ValidationError.intervalOutOfRange(syncIntervalMinutes)
        }
        for size in [messageBatchSize, contactBatchSize] where !Self.batchSizeRange.contains(size) {
            throw ValidationError.batchSizeOutOfRange(size)
        }
        if let apiBaseURL {
            try HTTPSyncAPI.validate(apiBaseURL)
        }
    }
}

/// Keeps the configuration in a JSON file that only the current user can read.
public struct ConfigurationStore: Sendable {
    public let url: URL

    public init(url: URL = AppPaths.configurationFile) {
        self.url = url
    }

    /// The saved configuration, or the defaults if there is no file. A file with
    /// an invalid value causes an error, because a person can edit the file.
    public func load() throws -> SyncConfiguration {
        guard PrivateFile.exists(url) else { return SyncConfiguration() }
        let configuration = try JSONCoding.storageDecoder().decode(SyncConfiguration.self, from: Data(contentsOf: url))
        try configuration.validate()
        return configuration
    }

    /// Validates the configuration, then saves it.
    public func save(_ configuration: SyncConfiguration) throws {
        try configuration.validate()
        try PrivateFile.write(JSONCoding.storageEncoder().encode(configuration), to: url)
    }
}

/// The files that isync keeps for the current user.
public enum AppPaths {
    public static var directory: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return base.appending(path: "isync", directoryHint: .isDirectory)
    }

    public static var stateFile: URL { directory.appending(path: "state.json") }
    public static var configurationFile: URL { directory.appending(path: "config.json") }
}
