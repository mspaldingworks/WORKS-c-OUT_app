import Foundation

/// Where an account keeps its documents: uploaded résumés and cover letters,
/// and the cover letter and résumé PDFs WORKS(c)OUT writes. Mirrors the API's
/// `DocumentSettings.storage`.
public enum DocumentStorage: String, Codable, CaseIterable, Identifiable, Sendable {
    case both
    case app
    case drive

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .both: return "WORKS(c)OUT and Google Drive"
        case .app: return "WORKS(c)OUT only"
        case .drive: return "Google Drive only"
        }
    }

    /// Unknown values from a newer server read as the default.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DocumentStorage(rawValue: raw) ?? .both
    }
}

public struct DocumentSettings: Codable, Equatable, Sendable {
    public var storage: DocumentStorage
    /// Drive is connected (or, for the owner, the server's Drive is set up),
    /// so the Drive options can be chosen.
    public var driveAvailable: Bool

    public init(storage: DocumentStorage = .both, driveAvailable: Bool = false) {
        self.storage = storage
        self.driveAvailable = driveAvailable
    }

    enum CodingKeys: String, CodingKey { case storage, driveAvailable }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storage = try container.decodeIfPresent(DocumentStorage.self, forKey: .storage) ?? .both
        driveAvailable = try container.decodeIfPresent(Bool.self, forKey: .driveAvailable) ?? false
    }
}

/// How the cover-letter library is ordered. Mirrors the API's `sort`.
public enum CoverLetterSort: String, CaseIterable, Identifiable, Sendable {
    case newest, oldest, company, role

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .company: return "Company A–Z"
        case .role: return "Role A–Z"
        }
    }
}

/// Which letters the library shows. Mirrors the API's `source`.
public enum CoverLetterSource: String, CaseIterable, Identifiable, Sendable {
    case all, generated, uploaded

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "All letters"
        case .generated: return "Written by WORKS(c)OUT"
        case .uploaded: return "Uploaded by you"
        }
    }
}

/// One letter in the library: written here for a job, or uploaded.
public struct CoverLetterEntry: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    /// "generated" or "uploaded".
    public var source: String
    public var title: String
    public var company: String
    public var createdAt: Date
    /// The application's stage ("Applied", "Not applied yet", …); blank for uploads.
    public var status: String
    /// The full letter, for letters written here. Blank for uploads — the
    /// file is the letter.
    public var text: String
    public var preview: String
    /// Token-authenticated download of the copy kept in WORKS(c)OUT; blank
    /// when it's kept only in Drive.
    public var fileUrl: String
    public var driveUrl: String
    /// "app", "drive" or "both".
    public var storedIn: String

    public var isGenerated: Bool { source == "generated" }
    public var isInApp: Bool { storedIn != "drive" && !fileUrl.isEmpty }
    public var isInDrive: Bool { storedIn != "app" && !driveUrl.isEmpty }

    enum CodingKeys: String, CodingKey {
        case id, source, title, company, createdAt, status, text, preview, fileUrl, driveUrl, storedIn
    }

    /// Lenient: an older or newer server may leave a field out, and one odd
    /// row must not empty the whole library.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "generated"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        preview = try c.decodeIfPresent(String.self, forKey: .preview) ?? ""
        fileUrl = try c.decodeIfPresent(String.self, forKey: .fileUrl) ?? ""
        driveUrl = try c.decodeIfPresent(String.self, forKey: .driveUrl) ?? ""
        storedIn = try c.decodeIfPresent(String.self, forKey: .storedIn) ?? "app"
    }
}
