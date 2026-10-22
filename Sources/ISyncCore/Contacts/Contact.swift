import Foundation

/// A contact card, in the shape that the API gets.
public struct Contact: Codable, Equatable, Sendable {
    /// The identifier that Contacts gives the card. It is stable on one Mac.
    public var id: String
    public var givenName: String?
    public var middleName: String?
    public var familyName: String?
    public var nickname: String?
    public var organization: String?
    public var jobTitle: String?
    public var phones: [LabeledValue]
    public var emails: [LabeledValue]
    public var postalAddresses: [PostalAddress]
    /// "YYYY-MM-DD", or "--MM-DD" when the card has no year.
    public var birthday: String?

    public init(
        id: String,
        givenName: String? = nil,
        middleName: String? = nil,
        familyName: String? = nil,
        nickname: String? = nil,
        organization: String? = nil,
        jobTitle: String? = nil,
        phones: [LabeledValue] = [],
        emails: [LabeledValue] = [],
        postalAddresses: [PostalAddress] = [],
        birthday: String? = nil
    ) {
        self.id = id
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.nickname = nickname
        self.organization = organization
        self.jobTitle = jobTitle
        self.phones = phones
        self.emails = emails
        self.postalAddresses = postalAddresses
        self.birthday = birthday
    }
}

public struct LabeledValue: Codable, Equatable, Sendable {
    /// A label such as "mobile" or "work", if the card has one.
    public var label: String?
    public var value: String

    public init(label: String? = nil, value: String) {
        self.label = label
        self.value = value
    }
}

public struct PostalAddress: Codable, Equatable, Sendable {
    public var label: String?
    public var street: String?
    public var city: String?
    public var state: String?
    public var postalCode: String?
    public var country: String?
    public var isoCountryCode: String?

    public init(
        label: String? = nil,
        street: String? = nil,
        city: String? = nil,
        state: String? = nil,
        postalCode: String? = nil,
        country: String? = nil,
        isoCountryCode: String? = nil
    ) {
        self.label = label
        self.street = street
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
        self.isoCountryCode = isoCountryCode
    }
}

/// A source of contact cards.
public protocol ContactSource: Sendable {
    /// All contact cards. Throw an error if access is not authorized. Do not
    /// return an empty list in that case.
    func contacts() async throws -> [Contact]
}
