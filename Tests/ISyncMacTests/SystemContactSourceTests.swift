import Contacts
import ISyncCore
import XCTest

@testable import ISyncMac

final class SystemContactSourceTests: XCTestCase {
    /// A label must not depend on the system language. Else a language change gives a new hash for
    /// each card, and the next sync sends all cards again.
    func testSystemLabelsBecomeStableNames() {
        let cases: [(String?, String?)] = [
            (CNLabelPhoneNumberMobile, "Mobile"),
            (CNLabelHome, "Home"),
            ("Boat phone", "Boat phone"),
            ("_$!<>!$_", "_$!<>!$_"),
            ("", nil),
            (nil, nil),
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(SystemContactSource.label(raw), expected, String(describing: raw))
        }
    }

    func testBirthdaysUseTheAPIFormat() {
        XCTAssertEqual(SystemContactSource.birthday(from: DateComponents(year: 1990, month: 4, day: 2)), "1990-04-02")
        XCTAssertEqual(SystemContactSource.birthday(from: DateComponents(month: 12, day: 25)), "--12-25")
        XCTAssertNil(SystemContactSource.birthday(from: DateComponents(year: 1990)))
    }

    func testMapsACardToTheAPIShape() {
        let card = CNMutableContact()
        card.givenName = "Ana"
        card.familyName = "Lopez"
        card.phoneNumbers = [
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+15555550100"))
        ]
        card.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: "ana@example.com" as NSString)]

        let contact = SystemContactSource.contact(from: card)

        XCTAssertEqual(contact.id, card.identifier)
        XCTAssertEqual(contact.givenName, "Ana")
        XCTAssertNil(contact.middleName, "an empty field is nil")
        XCTAssertEqual(contact.phones, [LabeledValue(label: "Mobile", value: "+15555550100")])
        XCTAssertEqual(contact.emails, [LabeledValue(label: "Work", value: "ana@example.com")])
    }
}
