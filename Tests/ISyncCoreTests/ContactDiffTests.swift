import XCTest

@testable import ISyncCore

final class ContactDiffTests: XCTestCase {
    func testFindsNewChangedAndDeletedCardsAndSkipsUnchangedCards() throws {
        let unchanged = Contact(
            id: "same", givenName: "Ana", phones: [LabeledValue(label: "mobile", value: "+15550000001")])
        let original = Contact(id: "edit", givenName: "Bo")
        let previous = try ContactDiff.changes(
            current: [unchanged, original, Contact(id: "gone")], previousHashes: [:])

        var edited = original
        edited.emails = [LabeledValue(value: "bo@example.com")]
        let added = Contact(id: "new", familyName: "Cy")
        let changes = try ContactDiff.changes(current: [unchanged, edited, added], previousHashes: previous.hashes)

        XCTAssertEqual(changes.upserts.map(\.id), ["edit", "new"])
        XCTAssertEqual(changes.deletedIDs, ["gone"])
        XCTAssertEqual(Set(changes.hashes.keys), ["same", "edit", "new"])
        XCTAssertEqual(changes.hashes["same"], previous.hashes["same"])
    }
}
