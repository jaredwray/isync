import Foundation

/// The contact changes since the last sync.
public struct ContactChanges: Equatable, Sendable {
    /// New and changed cards, in source order.
    public var upserts: [Contact]
    /// The IDs of cards that the source no longer has, in sorted order.
    public var deletedIDs: [String]
    /// The content hash of each current card, by ID.
    public var hashes: [String: String]

    public var isEmpty: Bool { upserts.isEmpty && deletedIDs.isEmpty }
}

/// Finds new, changed, and deleted contacts from content hashes.
public enum ContactDiff {
    public static func changes(current: [Contact], previousHashes: [String: String]) throws -> ContactChanges {
        let encoder = JSONCoding.hashEncoder()
        var hashes: [String: String] = [:]
        var upserts: [Contact] = []
        for contact in current {
            let hash = FNV1a.hexDigest(try encoder.encode(contact))
            hashes[contact.id] = hash
            if previousHashes[contact.id] != hash {
                upserts.append(contact)
            }
        }
        let deletedIDs = previousHashes.keys.filter { hashes[$0] == nil }.sorted()
        return ContactChanges(upserts: upserts, deletedIDs: deletedIDs, hashes: hashes)
    }
}
