import Foundation

/// Which optional Job-Feed filters an account wants surfaced. Mirrors the API's
/// `api/identity/filter-preferences/` shape. The client decodes with
/// `.convertFromSnakeCase` and encodes with `.convertToSnakeCase`, so property
/// names stay camelCase here and map to `job_type` / `match_score` on the wire.
public struct JobFilterPreferences: Codable, Equatable, Sendable {
    public var salary: Bool
    public var remote: Bool
    public var jobType: Bool
    public var matchScore: Bool

    public init(salary: Bool = true, remote: Bool = false,
                jobType: Bool = false, matchScore: Bool = false) {
        self.salary = salary
        self.remote = remote
        self.jobType = jobType
        self.matchScore = matchScore
    }

    /// Lenient decode: an older or newer server row might omit a key this client
    /// doesn't share, and a missing filter should default off (salary on) rather
    /// than fail the whole decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        salary = try container.decodeIfPresent(Bool.self, forKey: .salary) ?? true
        remote = try container.decodeIfPresent(Bool.self, forKey: .remote) ?? false
        jobType = try container.decodeIfPresent(Bool.self, forKey: .jobType) ?? false
        matchScore = try container.decodeIfPresent(Bool.self, forKey: .matchScore) ?? false
    }

    /// True when the user has hidden every filter — the feed shows no bar at all.
    public var isNoneEnabled: Bool { !(salary || remote || jobType || matchScore) }
}

/// The concrete selections applied to one Job-Feed request, translated to the
/// query params the postings endpoint understands. Only the facets the user has
/// enabled (see `JobFilterPreferences`) are ever populated by the UI.
public struct JobFilterQuery: Equatable, Sendable {
    /// Annual salary floor / ceiling. A nil bound is open-ended on that side.
    public var salaryMin: Int?
    public var salaryMax: Int?
    /// Keep postings that list no pay at all. On by default, so turning on a
    /// salary filter doesn't silently hide most of the feed.
    public var includeUnspecifiedSalary: Bool
    public var remoteOnly: Bool
    /// Normalized job-type tokens, e.g. "full_time", "contract".
    public var jobTypes: [String]
    /// Minimum fit score, 0–100.
    public var minScore: Int?

    public init(salaryMin: Int? = nil, salaryMax: Int? = nil,
                includeUnspecifiedSalary: Bool = true,
                remoteOnly: Bool = false, jobTypes: [String] = [], minScore: Int? = nil) {
        self.salaryMin = salaryMin
        self.salaryMax = salaryMax
        self.includeUnspecifiedSalary = includeUnspecifiedSalary
        self.remoteOnly = remoteOnly
        self.jobTypes = jobTypes
        self.minScore = minScore
    }

    /// True when nothing here actually constrains the feed.
    public var isEmpty: Bool {
        salaryMin == nil && salaryMax == nil && !remoteOnly && jobTypes.isEmpty && minScore == nil
    }

    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let salaryMin { items.append(URLQueryItem(name: "salary_min", value: String(salaryMin))) }
        if let salaryMax { items.append(URLQueryItem(name: "salary_max", value: String(salaryMax))) }
        // The flag only means anything when a salary bound is set.
        if (salaryMin != nil || salaryMax != nil) && !includeUnspecifiedSalary {
            items.append(URLQueryItem(name: "include_unspecified_salary", value: "0"))
        }
        if remoteOnly { items.append(URLQueryItem(name: "remote", value: "1")) }
        for type in jobTypes {
            items.append(URLQueryItem(name: "job_type", value: type))
        }
        if let minScore { items.append(URLQueryItem(name: "min_score", value: String(minScore))) }
        return items
    }
}
