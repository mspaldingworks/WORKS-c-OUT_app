import Foundation

public struct Company: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public var name: String
    public var website: String
    public var notes: String
    public let createdAt: Date
    public var contacts: [Contact]

    public init(id: Int, name: String, website: String = "", notes: String = "", createdAt: Date = .now, contacts: [Contact] = []) {
        self.id = id
        self.name = name
        self.website = website
        self.notes = notes
        self.createdAt = createdAt
        self.contacts = contacts
    }
}

public struct Contact: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public var company: Int
    public var name: String
    public var role: String
    public var email: String
    public var phone: String
    public var notes: String
}
