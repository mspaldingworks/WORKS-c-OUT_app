import Foundation

public struct Application: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case saved
        case ready
        case approved
        case applied
        case discarded
        case phoneScreen = "phone_screen"
        case interview
        case offer
        case rejected
        case withdrawn

        public var label: String {
            switch self {
            case .saved: return "Saved"
            case .ready: return "Draft ready"
            case .approved: return "Approved"
            case .applied: return "Applied"
            case .discarded: return "Removed"
            case .phoneScreen: return "Phone screen"
            case .interview: return "Interview"
            case .offer: return "Offer"
            case .rejected: return "Rejected"
            case .withdrawn: return "Withdrawn"
            }
        }
    }

    public enum Source: String, Codable, Sendable {
        case manual
        case ingested
    }

    public let id: Int
    public var company: Int
    public var companyName: String
    public var roleTitle: String
    public var jobUrl: String
    public var status: Status
    public var source: Source
    public var appliedDate: String?
    public var salaryNotes: String
    /// Where the employer actually takes applications — resolved server-side
    /// from the source posting, falling back to the job listing.
    public var applyUrl: String
    public var generatedMaterials: ApplicationMaterials?
    public var resumeDriveUrl: String
    public var coverLetterDriveUrl: String
    public var notes: String
    public let createdAt: Date
    public let updatedAt: Date
    public var events: [ApplicationEvent]

    enum CodingKeys: String, CodingKey {
        case id, company, companyName, roleTitle, jobUrl, status, source
        case appliedDate, salaryNotes, applyUrl, generatedMaterials
        case resumeDriveUrl, coverLetterDriveUrl, notes, createdAt, updatedAt, events
    }

    /// Decodes leniently, for the same reason ApplicationMaterials does: fields
    /// added to the API later (apply_url, the Drive links) are absent from any
    /// older or leaner payload, and the synthesised initialiser would throw on
    /// the whole response rather than leave one string empty.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        company = try container.decode(Int.self, forKey: .company)
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName) ?? ""
        roleTitle = try container.decodeIfPresent(String.self, forKey: .roleTitle) ?? ""
        jobUrl = try container.decodeIfPresent(String.self, forKey: .jobUrl) ?? ""
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .saved
        source = try container.decodeIfPresent(Source.self, forKey: .source) ?? .manual
        appliedDate = try container.decodeIfPresent(String.self, forKey: .appliedDate)
        salaryNotes = try container.decodeIfPresent(String.self, forKey: .salaryNotes) ?? ""
        applyUrl = try container.decodeIfPresent(String.self, forKey: .applyUrl) ?? ""
        generatedMaterials = try container.decodeIfPresent(
            ApplicationMaterials.self, forKey: .generatedMaterials)
        resumeDriveUrl = try container.decodeIfPresent(String.self, forKey: .resumeDriveUrl) ?? ""
        coverLetterDriveUrl = try container.decodeIfPresent(
            String.self, forKey: .coverLetterDriveUrl) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        events = try container.decodeIfPresent([ApplicationEvent].self, forKey: .events) ?? []
    }

    public init(
        id: Int,
        company: Int,
        companyName: String,
        roleTitle: String,
        jobUrl: String = "",
        status: Status = .saved,
        source: Source = .manual,
        appliedDate: String? = nil,
        salaryNotes: String = "",
        applyUrl: String = "",
        generatedMaterials: ApplicationMaterials? = nil,
        resumeDriveUrl: String = "",
        coverLetterDriveUrl: String = "",
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        events: [ApplicationEvent] = []
    ) {
        self.id = id
        self.company = company
        self.companyName = companyName
        self.roleTitle = roleTitle
        self.jobUrl = jobUrl
        self.status = status
        self.source = source
        self.appliedDate = appliedDate
        self.salaryNotes = salaryNotes
        self.applyUrl = applyUrl
        self.generatedMaterials = generatedMaterials
        self.resumeDriveUrl = resumeDriveUrl
        self.coverLetterDriveUrl = coverLetterDriveUrl
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.events = events
    }
}

public struct ApplicationEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public var application: Int
    public var note: String
    public let occurredAt: Date
}

/// Payload for creating an application — omits server-assigned fields.
public struct NewApplication: Encodable, Sendable {
    public var company: Int
    public var roleTitle: String
    public var jobUrl: String

    public init(company: Int, roleTitle: String, jobUrl: String = "") {
        self.company = company
        self.roleTitle = roleTitle
        self.jobUrl = jobUrl
    }
}

public struct NewCompany: Encodable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public extension Application {
    /// Waiting on her to read and approve. Includes `saved` so an application
    /// added by hand enters the pipeline at the same place a scraped one does.
    var isDraft: Bool { status == .saved || status == .ready }

    /// Approved and waiting to be sent.
    var isApproved: Bool { status == .approved }

    /// Everything she has actually submitted, including the outcomes. Distinct
    /// from `isDraft`: these are done and being tracked, not waiting on her.
    var isSubmitted: Bool {
        switch status {
        case .applied, .phoneScreen, .interview, .offer, .rejected, .withdrawn: return true
        case .saved, .ready, .approved, .discarded: return false
        }
    }

    /// Statuses worth offering as the next step from wherever this one is.
    var nextSteps: [Status] {
        switch status {
        case .applied: return [.phoneScreen, .interview, .rejected, .withdrawn]
        case .phoneScreen: return [.interview, .offer, .rejected, .withdrawn]
        case .interview: return [.offer, .rejected, .withdrawn]
        case .offer: return [.rejected, .withdrawn]
        default: return []
        }
    }

    var bestApplyLink: URL? {
        URL(string: applyUrl.isEmpty ? jobUrl : applyUrl)
    }

    var driveResumeLink: URL? { URL(string: resumeDriveUrl) }
    var driveCoverLetterLink: URL? { URL(string: coverLetterDriveUrl) }
}
