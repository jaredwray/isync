import Contacts
import Foundation
import ISyncCore

/// Reads the cards in the Contacts app with `CNContactStore`.
public struct SystemContactSource: ContactSource {
    public enum AccessError: Error, CustomStringConvertible {
        case notAuthorized

        public var description: String {
            "isync cannot read Contacts. Give it access in System Settings > Privacy & Security > Contacts."
        }
    }

    public init() {}

    public static var isAuthorized: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    /// Shows the system prompt if the person did not answer it before.
    public static func requestAccess() async throws -> Bool {
        try await CNContactStore().requestAccess(for: .contacts)
    }

    public func contacts() async throws -> [Contact] {
        guard Self.isAuthorized else { throw AccessError.notAuthorized }
        return try await Task.detached(priority: .utility) {
            try Self.fetchAll()
        }.value
    }

    private static func fetchAll() throws -> [Contact] {
        let keys = [
            CNContactGivenNameKey,
            CNContactMiddleNameKey,
            CNContactFamilyNameKey,
            CNContactNicknameKey,
            CNContactOrganizationNameKey,
            CNContactJobTitleKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactPostalAddressesKey,
            CNContactBirthdayKey,
        ].map { $0 as CNKeyDescriptor }
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .none
        let accumulator = Accumulator()
        try CNContactStore().enumerateContacts(with: request) { card, _ in
            accumulator.contacts.append(contact(from: card))
        }
        return accumulator.contacts
    }

    static func contact(from card: CNContact) -> Contact {
        Contact(
            id: card.identifier,
            givenName: card.givenName.nilIfEmpty,
            middleName: card.middleName.nilIfEmpty,
            familyName: card.familyName.nilIfEmpty,
            nickname: card.nickname.nilIfEmpty,
            organization: card.organizationName.nilIfEmpty,
            jobTitle: card.jobTitle.nilIfEmpty,
            phones: card.phoneNumbers.map { LabeledValue(label: label($0.label), value: $0.value.stringValue) },
            emails: card.emailAddresses.map { LabeledValue(label: label($0.label), value: $0.value as String) },
            postalAddresses: card.postalAddresses.map { item in
                let address = item.value
                return PostalAddress(
                    label: label(item.label),
                    street: address.street.nilIfEmpty,
                    city: address.city.nilIfEmpty,
                    state: address.state.nilIfEmpty,
                    postalCode: address.postalCode.nilIfEmpty,
                    country: address.country.nilIfEmpty,
                    isoCountryCode: address.isoCountryCode.nilIfEmpty
                )
            },
            birthday: card.birthday.flatMap(birthday(from:))
        )
    }

    /// Contacts stores system labels as "_$!<Mobile>!$_". This returns "Mobile".
    /// The value does not change with the system language, so the content hash stays stable.
    static func label(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let prefix = "_$!<"
        let suffix = ">!$_"
        guard raw.hasPrefix(prefix), raw.hasSuffix(suffix), raw.count > prefix.count + suffix.count else {
            return raw
        }
        return String(raw.dropFirst(prefix.count).dropLast(suffix.count))
    }

    static func birthday(from components: DateComponents) -> String? {
        guard let month = components.month, let day = components.day else { return nil }
        let monthDay = String(format: "%02d-%02d", month, day)
        guard let year = components.year else { return "--" + monthDay }
        return String(format: "%04d-", year) + monthDay
    }
}

/// Collects cards in the enumeration block. `enumerateContacts` calls the block on the
/// current thread and returns after the last call, so no lock is necessary.
private final class Accumulator: @unchecked Sendable {
    var contacts: [Contact] = []
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
