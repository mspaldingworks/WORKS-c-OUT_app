import Foundation

public enum WorksCoutAPIError: Error, Equatable, Sendable {
    case notAuthenticated
    case notFound
    case badStatus(Int)
    /// The server can't do this yet and said why (e.g. no API key configured).
    case unavailable(String)
    case decodingFailed
    case transport
}

/// Talks to the Job Search API (see Famiy_Appily_api's `api/` Django service).
/// Uses DRF TokenAuthentication — a single long-lived token stored in the
/// Keychain, not a login flow, consistent with the rest of Family Appily
/// having no accounts. This is the only part of the app that makes network
/// calls; everything else (chores, rotation, tickets) is local/CloudKit.
public actor WorksCoutAPIClient {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var token: String

        public init(baseURL: URL, token: String) {
            self.baseURL = baseURL
            self.token = token
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = WorksCoutAPIClient.fractionalFormatter.date(from: string) { return date }
            if let date = WorksCoutAPIClient.formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
        }
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: Applications

    public func fetchApplications() async throws -> [Application] {
        try await request("api/tracker/applications/")
    }

    public func createApplication(_ new: NewApplication) async throws -> Application {
        try await request("api/tracker/applications/", method: "POST", body: new)
    }

    // MARK: Companies

    public func fetchCompanies() async throws -> [Company] {
        try await request("api/tracker/companies/")
    }

    public func createCompany(_ new: NewCompany) async throws -> Company {
        try await request("api/tracker/companies/", method: "POST", body: new)
    }

    // MARK: Ingestion (RSS job feed)

    /// Filtering server-side matters once the scrapers run daily — otherwise the
    /// feed pulls every posting ever ingested just to show the new ones.
    public func fetchIngestedPostings(status: IngestedPosting.Status? = nil) async throws -> [IngestedPosting] {
        let query = status.map { [URLQueryItem(name: "status", value: $0.rawValue)] } ?? []
        return try await request("api/ingestion/postings/", queryItems: query)
    }

    /// Tailored cover letter and resume for a posting. Cached server-side after
    /// the first call, so re-opening a posting doesn't re-run generation.
    public func generateMaterials(postingID: Int, refresh: Bool = false) async throws -> ApplicationMaterials {
        // Generation is one long model call — well past URLSession's 60s
        // default, which would surface as a transport error while the server is
        // still working (and still being billed for it).
        try await request(
            "api/ingestion/postings/\(postingID)/materials/",
            method: "POST",
            queryItems: refresh ? [URLQueryItem(name: "refresh", value: "1")] : [],
            timeout: 300
        )
    }

    /// Queue several postings for application in one go. Returns immediately
    /// with a job to poll — generation is ~40s each, so a batch runs server-side
    /// on a background thread rather than holding the request open.
    public func prepareApplications(postingIDs: [Int]) async throws -> PrepareJob {
        try await request(
            "api/tracker/applications/prepare/",
            method: "POST",
            body: PrepareRequest(postingIds: postingIDs)
        )
    }

    public func prepareStatus(jobID: String) async throws -> PrepareJob {
        try await request("api/tracker/applications/prepare/\(jobID)/")
    }

    /// Record that she's read and okayed a draft. Sends nothing anywhere.
    public func approveApplication(id: Int) async throws -> Application {
        try await request("api/tracker/applications/\(id)/approve/", method: "POST")
    }

    /// Replace the generated text with her own wording, then re-render the PDFs.
    public func editMaterials(applicationID: Int, materials: ApplicationMaterials) async throws -> Application {
        try await request(
            "api/tracker/applications/\(applicationID)/materials/",
            method: "PATCH",
            body: materials,
            // Re-renders two PDFs and re-uploads both to Drive before replying.
            timeout: 120
        )
    }

    public func markApplied(applicationID: Int) async throws -> Application {
        try await request("api/tracker/applications/\(applicationID)/mark-applied/", method: "POST")
    }

    /// Move an application along the pipeline — phone screen, interview, offer.
    public func updateStatus(applicationID: Int, status: Application.Status) async throws -> Application {
        struct Patch: Encodable { let status: String }
        return try await request(
            "api/tracker/applications/\(applicationID)/",
            method: "PATCH",
            body: Patch(status: status.rawValue)
        )
    }

    public func syncSheet() async throws -> Int {
        struct Result: Decodable { let synced: Int }
        let result: Result = try await request("api/tracker/applications/sync-sheet/", method: "POST")
        return result.synced
    }

    /// Take a posting out of the feed. Reversible with `restorePosting`.
    public func dismissPosting(id: Int) async throws -> IngestedPosting {
        try await request("api/ingestion/postings/\(id)/dismiss/", method: "POST")
    }

    public func restorePosting(id: Int) async throws -> IngestedPosting {
        try await request("api/ingestion/postings/\(id)/restore/", method: "POST")
    }

    /// Remove an application from the pipeline. Not a delete — the generated
    /// text cost money and undo has to be able to put it back.
    public func discardApplication(id: Int) async throws -> Application {
        try await request("api/tracker/applications/\(id)/discard/", method: "POST")
    }

    public func restoreApplication(id: Int) async throws -> Application {
        try await request("api/tracker/applications/\(id)/restore/", method: "POST")
    }

    public func promotePosting(id: Int) async throws -> Application {
        try await request("api/ingestion/postings/\(id)/promote/", method: "POST")
    }

    // MARK: Identity

    public func fetchProfiles() async throws -> [ProfessionalProfile] {
        try await request("api/identity/profile/")
    }

    public func fetchSkills() async throws -> [Skill] {
        try await request("api/identity/skills/")
    }

    public func fetchLinks() async throws -> [ProfileLink] {
        try await request("api/identity/links/")
    }

    public func fetchResumes() async throws -> [ResumeVersion] {
        try await request("api/identity/resumes/")
    }

    // MARK: Request plumbing

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: (some Encodable)? = Optional<Int>.none,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        // Query items go through URLComponents rather than being appended to the
        // path — appendingPathComponent would percent-encode the "?" and produce
        // a URL the API can't route.
        let base = configuration.baseURL.appendingPathComponent(path)
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else { throw WorksCoutAPIError.transport }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Token \(configuration.token)", forHTTPHeaderField: "Authorization")
        if let timeout { urlRequest.timeoutInterval = timeout }

        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw WorksCoutAPIError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw WorksCoutAPIError.transport }
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw WorksCoutAPIError.notAuthenticated
        case 404:
            throw WorksCoutAPIError.notFound
        case 503:
            // Carries an actionable reason ("no API key configured", "no master
            // resume saved") — surfacing it beats a bare status code.
            let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"]
            throw WorksCoutAPIError.unavailable(detail ?? "This isn't available yet.")
        default:
            throw WorksCoutAPIError.badStatus(http.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw WorksCoutAPIError.decodingFailed
        }
    }
}
