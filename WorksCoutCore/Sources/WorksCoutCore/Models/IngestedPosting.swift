import Foundation

public struct IngestedPosting: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case new
        case triaged
        case dismissed
    }

    public let id: Int
    public var source: String
    public var title: String
    public var companyName: String
    public var url: String
    /// The employer's ATS link — where the application form actually lives.
    /// Falls back to the listing URL when the board didn't expose one.
    public var applyUrl: String
    public var status: Status
    /// Fit against her profile, 0-100, computed server-side at ingest.
    public var score: Int
    /// Why it scored that way, so the ranking can be judged rather than trusted.
    public var scoreReasons: [String]
    /// Which ATS the application goes through, and whether it demands an
    /// account before showing the form.
    public var platform: String
    public var requiresAccount: Bool
    public var signInUrl: String
    /// The readable parts of the scrape, for the expanded card. Replaces the
    /// raw scraper payload the feed used to ship and never decoded.
    public var details: PostingDetails?
    /// Which of her skills this posting asks for, and which it asks for that
    /// she doesn't list.
    public var skills: PostingSkills?
    public let createdAt: Date

    /// Where the Apply button should send her.
    public var bestApplyLink: URL? {
        URL(string: applyUrl.isEmpty ? url : applyUrl)
    }
}

/// Tailored application materials generated for one posting.
/// Her skills against one posting. Two separate counts, because a job matching
/// a dozen of her skills still isn't much use if it wants four she's never
/// touched.
public struct PostingSkills: Codable, Equatable, Sendable {
    public var matched: [String]
    public var missing: [String]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matched = try container.decodeIfPresent([String].self, forKey: .matched) ?? []
        missing = try container.decodeIfPresent([String].self, forKey: .missing) ?? []
    }

    public init(matched: [String] = [], missing: [String] = []) {
        self.matched = matched
        self.missing = missing
    }

    public var hasAnything: Bool { !matched.isEmpty || !missing.isEmpty }
}

/// What the expanded job card shows. Every field is optional in practice —
/// scrapers omit plenty — so all of them default rather than throwing.
public struct PostingDetails: Codable, Equatable, Sendable {
    public var description: String
    public var location: String
    public var salary: String
    public var jobTypes: [String]
    public var benefits: [String]
    public var requirements: [String]
    public var shifts: [String]
    public var posted: String
    public var isRemote: Bool
    public var companyRating: String

    enum CodingKeys: String, CodingKey {
        case description, location, salary, jobTypes, benefits
        case requirements, shifts, posted, isRemote, companyRating
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        salary = try container.decodeIfPresent(String.self, forKey: .salary) ?? ""
        jobTypes = try container.decodeIfPresent([String].self, forKey: .jobTypes) ?? []
        benefits = try container.decodeIfPresent([String].self, forKey: .benefits) ?? []
        requirements = try container.decodeIfPresent([String].self, forKey: .requirements) ?? []
        shifts = try container.decodeIfPresent([String].self, forKey: .shifts) ?? []
        posted = try container.decodeIfPresent(String.self, forKey: .posted) ?? ""
        isRemote = try container.decodeIfPresent(Bool.self, forKey: .isRemote) ?? false
        companyRating = try container.decodeIfPresent(String.self, forKey: .companyRating) ?? ""
    }

    /// The one-line facts worth showing on the collapsed card.
    public var summaryChips: [String] {
        var chips: [String] = []
        if isRemote { chips.append("Remote") }
        if !location.isEmpty, !isRemote || location.lowercased() != "remote" {
            chips.append(location)
        }
        if !salary.isEmpty { chips.append(salary) }
        chips.append(contentsOf: jobTypes.filter { $0.lowercased() != "remote" })
        return chips
    }

    public var hasAnything: Bool {
        !description.isEmpty || !summaryChips.isEmpty || !benefits.isEmpty
    }
}

public extension IngestedPosting {
    /// Where to create an account, when the portal insists on one before it
    /// will show the form.
    var signInLink: URL? { URL(string: signInUrl) }
}

public struct ApplicationMaterials: Codable, Equatable, Sendable {
    public var coverLetter: String
    public var resumeSummary: String
    public var resumeBullets: [String]
    public var gaps: [String]
    /// True when the model's output didn't match the expected section format —
    /// the letter field then holds the whole response rather than losing it.
    public var unparsed: Bool

    // Raw values are camelCase on purpose: the client decodes with
    // .convertFromSnakeCase, so "cover_letter" has already become
    // "coverLetter" by the time these are matched.
    enum CodingKeys: String, CodingKey {
        case coverLetter, resumeSummary, resumeBullets, gaps, unparsed
    }

    /// Decodes leniently. A record with no materials used to arrive as `{}` —
    /// an object claiming to be materials while missing every field — and the
    /// strict synthesised initialiser threw, which failed the decode of the
    /// whole list and emptied the Drafts screen. One malformed row should cost
    /// its own contents, not everything alongside it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coverLetter = try container.decodeIfPresent(String.self, forKey: .coverLetter) ?? ""
        resumeSummary = try container.decodeIfPresent(String.self, forKey: .resumeSummary) ?? ""
        resumeBullets = try container.decodeIfPresent([String].self, forKey: .resumeBullets) ?? []
        gaps = try container.decodeIfPresent([String].self, forKey: .gaps) ?? []
        unparsed = try container.decodeIfPresent(Bool.self, forKey: .unparsed) ?? false
    }

    public init(coverLetter: String = "", resumeSummary: String = "",
                resumeBullets: [String] = [], gaps: [String] = [],
                unparsed: Bool = false) {
        self.coverLetter = coverLetter
        self.resumeSummary = resumeSummary
        self.resumeBullets = resumeBullets
        self.gaps = gaps
        self.unparsed = unparsed
    }

    /// True when there's nothing worth showing, however it arrived.
    public var isEmpty: Bool {
        coverLetter.isEmpty && resumeSummary.isEmpty && resumeBullets.isEmpty && gaps.isEmpty
    }
}


/// Payload for starting a bulk prepare run.
public struct PrepareRequest: Codable, Sendable {
    public var postingIds: [Int]
}

/// Progress of a bulk prepare run. `results` fills in as each posting finishes,
/// so the UI can show which ones are done rather than one opaque spinner.
public struct PrepareJob: Codable, Equatable, Sendable, Identifiable {
    public struct Result: Codable, Equatable, Sendable {
        public var postingId: Int
        public var ok: Bool
        public var detail: String
        public var applicationId: Int?
    }

    public var id: String
    public var state: String
    public var total: Int
    public var done: Int
    public var results: [Result]

    public var isFinished: Bool { state == "finished" }
    public var failures: [Result] { results.filter { !$0.ok } }
}
