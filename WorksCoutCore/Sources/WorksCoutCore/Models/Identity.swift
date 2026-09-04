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

public struct NewSkill: Encodable, Sendable {
    public var name: String
    public var category: String
    public var proficiency: Skill.Proficiency

    public init(name: String, category: String = "", proficiency: Skill.Proficiency = .competent) {
        self.name = name
        self.category = category
        self.proficiency = proficiency
    }
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

/// AI-suggested skills and contact fields extracted from one uploaded résumé.
/// Never written into Skill/ProfessionalProfile automatically — she reviews
/// and adds whichever suggestions she wants, the same as typing them by hand.
public struct ParsedResumeData: Codable, Equatable, Sendable {
    public var skills: [ParsedSkillSuggestion]
    public var headline: String
    public var email: String
    public var phone: String
    public var linkedinUrl: String
    public var unparsed: Bool

    /// A never-parsed résumé decodes its `parsed_data: {}` into this same type
    /// with every field at its default — this distinguishes "not parsed yet"
    /// from "parsed and genuinely found nothing".
    public var hasContent: Bool {
        !skills.isEmpty || !headline.isEmpty || !email.isEmpty || !phone.isEmpty || !linkedinUrl.isEmpty || unparsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skills = try container.decodeIfPresent([ParsedSkillSuggestion].self, forKey: .skills) ?? []
        headline = try container.decodeIfPresent(String.self, forKey: .headline) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        linkedinUrl = try container.decodeIfPresent(String.self, forKey: .linkedinUrl) ?? ""
        unparsed = try container.decodeIfPresent(Bool.self, forKey: .unparsed) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case skills, headline, email, phone, linkedinUrl = "linkedin_url", unparsed
    }
}

public struct ParsedSkillSuggestion: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var category: String
    public var proficiency: Skill.Proficiency

    public var id: String { name }
}

public struct ResumeVersion: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public var title: String
    public var file: String
    public var notes: String
    public var parsedData: ParsedResumeData
    public let createdAt: Date
}
