import Foundation

public enum WorksCoutAPIError: Error, Equatable, Sendable {
    case notAuthenticated
    case notFound
    case badStatus(Int)
    /// The server can't do this yet and said why (e.g. no API key configured).
    case unavailable(String)
    /// The request itself was rejected — a résumé over the size cap, a
    /// duplicate skill name, a second professional profile — with the reason
    /// the server gave, so the UI can show it instead of a bare status code.
    case badRequest(String)
    case decodingFailed
    case transport
}

/// Talks to the WORKS(c)OUT API (see WORKS-c-OUT_api's `api/` Django service).
/// Uses DRF TokenAuthentication — one long-lived per-account token, not a
/// login flow. Server-side every row now belongs to a real account, so this
/// token is what identifies whose data comes back; the app itself still has
/// no login screen because there is exactly one account.
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
    /// feed pulls every posting ever ingested just to show the new ones. The
    /// optional `filter` adds salary/remote/job-type/score constraints as query
    /// params (see JobFilterQuery); only the facets the user has enabled populate it.
    public func fetchIngestedPostings(status: IngestedPosting.Status? = nil,
                                      filter: JobFilterQuery? = nil) async throws -> [IngestedPosting] {
        var query = status.map { [URLQueryItem(name: "status", value: $0.rawValue)] } ?? []
        if let filter { query.append(contentsOf: filter.queryItems) }
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

    /// Which Job-Feed filters this account wants surfaced. GET auto-creates the
    /// row server-side with defaults, so this always returns something to render.
    public func fetchFilterPreferences() async throws -> JobFilterPreferences {
        try await request("api/identity/filter-preferences/")
    }

    /// Toggle which filters appear in the Job Feed. Singleton per account, so
    /// there's no id — PATCH always updates "mine".
    public func updateFilterPreferences(_ preferences: JobFilterPreferences) async throws -> JobFilterPreferences {
        try await request("api/identity/filter-preferences/", method: "PATCH", body: preferences)
    }

    /// The account's own AI provider keys. Keys come back masked — the plaintext
    /// is never returned by the server.
    public func fetchAICredentials() async throws -> [AICredential] {
        try await request("api/identity/ai-credentials/")
    }

    /// Save (or replace) the key for a provider and make it the active one.
    public func saveAICredential(_ credential: NewAICredential) async throws -> AICredential {
        try await request("api/identity/ai-credentials/", method: "POST", body: credential)
    }

    /// Switch which saved provider is actually used.
    public func activateAICredential(id: Int) async throws -> AICredential {
        try await request("api/identity/ai-credentials/\(id)/activate/", method: "POST")
    }

    /// Remove a saved provider key. The server returns the deleted row (200), not
    /// an empty 204, so there's always a body to decode.
    @discardableResult
    public func deleteAICredential(id: Int) async throws -> AICredential {
        try await request("api/identity/ai-credentials/\(id)/", method: "DELETE")
    }

    // MARK: Google Drive

    /// This account's Drive connection status (never the token itself).
    public func fetchDriveConnection() async throws -> DriveConnection {
        try await request("api/identity/drive/")
    }

    /// The Google consent URL to open (in a web-auth session) to connect Drive.
    public func driveAuthURL() async throws -> URL {
        struct Payload: Decodable { let authUrl: String }
        let payload: Payload = try await request("api/identity/drive/connect/")
        guard let url = URL(string: payload.authUrl) else { throw WorksCoutAPIError.decodingFailed }
        return url
    }

    /// The Identity on/off toggle for saving drafts to Drive.
    public func setDriveEnabled(_ enabled: Bool) async throws -> DriveConnection {
        struct Body: Encodable { let enabled: Bool }
        return try await request("api/identity/drive/", method: "PATCH", body: Body(enabled: enabled))
    }

    /// Forget the Drive connection. Uploads stop until reconnected.
    @discardableResult
    public func disconnectDrive() async throws -> DriveConnection {
        try await request("api/identity/drive/disconnect/", method: "POST")
    }

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

    /// Uploads a résumé file. Multipart, not JSON — Django's file parser
    /// expects multipart/form-data for a FileField, and the server validates
    /// size/type/count itself regardless of what this client already checked.
    public func uploadResume(title: String, notes: String = "", fileData: Data,
                              filename: String, mimeType: String) async throws -> ResumeVersion {
        let boundary = "WorksCoutBoundary-\(UUID().uuidString)"
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("title", title)
        if !notes.isEmpty { appendField("notes", notes) }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var urlRequest = URLRequest(url: configuration.baseURL.appendingPathComponent("api/identity/resumes/"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Token \(configuration.token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = 60

        return try await perform(urlRequest)
    }

    /// Extract skill/profile suggestions from an uploaded résumé. Cached
    /// server-side after the first call; pass refresh to redo it. Nothing
    /// this returns is written anywhere — applying a suggestion is a normal
    /// createSkill call, same as typing it in by hand.
    public func parseResume(id: Int, refresh: Bool = false) async throws -> ParsedResumeData {
        try await request(
            "api/identity/resumes/\(id)/parse/",
            method: "POST",
            queryItems: refresh ? [URLQueryItem(name: "refresh", value: "1")] : [],
            timeout: 60
        )
    }

    public func createSkill(_ new: NewSkill) async throws -> Skill {
        try await request("api/identity/skills/", method: "POST", body: new)
    }

    /// Remove a résumé from the list. Not a delete — the row and its parsed
    /// suggestions survive so `restoreResume` can put them back.
    public func discardResume(id: Int) async throws -> ResumeVersion {
        try await request("api/identity/resumes/\(id)/discard/", method: "POST")
    }

    public func restoreResume(id: Int) async throws -> ResumeVersion {
        try await request("api/identity/resumes/\(id)/restore/", method: "POST")
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

        return try await perform(urlRequest)
    }

    private func perform<T: Decodable>(_ urlRequest: URLRequest) async throws -> T {
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
        case 400:
            throw WorksCoutAPIError.badRequest(Self.readableValidationMessage(from: data))
        case 401, 403:
            throw WorksCoutAPIError.notAuthenticated
        case 404:
            throw WorksCoutAPIError.notFound
        case 422:
            let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"]
            throw WorksCoutAPIError.badRequest(detail ?? "That file couldn't be read.")
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

    /// DRF validation errors come back as {"field": ["message", ...]} or
    /// {"non_field_errors": [...]} — never a single "detail" string like the
    /// 503/422 cases. Join every message across every field into one readable
    /// sentence rather than showing raw JSON.
    private static func readableValidationMessage(from data: Data) -> String {
        guard let fieldErrors = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return "That wasn't accepted."
        }
        let messages = fieldErrors.values.flatMap { $0 }
        return messages.isEmpty ? "That wasn't accepted." : messages.joined(separator: " ")
    }
}
