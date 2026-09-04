import Foundation

public struct ProfessionalProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public var headline: String
    public var summary: String
    public let updatedAt: Date
}

public struct Skill: Codable, Identifiable, Equatable, Sendable {
    public enum Proficiency: String, Codable, Sendable {
        case learning, competent, strong, expert
    }

    public let id: Int
    public var name: String
    public var category: String
    public var proficiency: Proficiency
}

public struct ProfileLink: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case active
        case needsUpdate = "needs_update"
        case stale
    }

    public let id: Int
    public var platform: String
    public var url: String
    public var status: Status
    public var notes: String
}

public struct ResumeVersion: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public var title: String
    public var file: String
    public var notes: String
    public let createdAt: Date
}
