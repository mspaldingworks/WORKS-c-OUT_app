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

/// What an uploaded document is. Résumés are read for skills; a cover letter
/// is a sample of the person's voice for drafts.
public enum DocumentKind: String, Codable, Sendable, CaseIterable {
    case resume
    case coverLetter = "cover_letter"

    /// Anything unrecognised is treated as a résumé, the original kind.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DocumentKind(rawValue: raw) ?? .resume
    }

    public var label: String { self == .resume ? "résumé" : "cover letter" }
}

public struct ResumeVersion: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    /// Optional so an older server that doesn't send it still decodes.
    public var kind: DocumentKind?
    public var title: String
    public var file: String
    public var notes: String
    public var parsedData: ParsedResumeData
    /// Where the Drive copy (or the Drive original) is; nil or blank when the
    /// document isn't in Drive.
    public var driveUrl: String?
    /// "app", "drive" or "both". Optional so an older server still decodes.
    public var storedIn: String?
    public let createdAt: Date

    public var isCoverLetter: Bool { kind == .coverLetter }
    public var isInDrive: Bool { !(driveUrl ?? "").isEmpty }
    public var isInApp: Bool { storedIn != "drive" }
}

/// What came of copying picked Drive files in: the documents made, and why
/// any others weren't taken.
public struct DriveImportResult: Decodable, Sendable {
    public struct Refusal: Decodable, Sendable {
        public var fileId: String
        public var name: String?
        public var detail: String
    }

    public var created: [ResumeVersion]
    public var refused: [Refusal]
}
