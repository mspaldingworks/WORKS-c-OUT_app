import Foundation

/// How the Job Feed is ordered. Mirrors the API's `sort` param and the `sort`
/// field on filter preferences, where the last choice is remembered.
public enum JobSort: String, Codable, CaseIterable, Identifiable, Sendable {
    case best
    case newest
    case pay
    case closest
    case company

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .best: return "Best match"
        case .newest: return "Newest"
        case .pay: return "Highest pay"
        case .closest: return "Closest"
        case .company: return "Company A–Z"
        }
    }

    public var systemImage: String {
        switch self {
        case .best: return "rosette"
        case .newest: return "clock"
        case .pay: return "dollarsign.circle"
        case .closest: return "location"
        case .company: return "textformat"
        }
    }

    /// An unknown value from a newer server falls back to best match rather
    /// than failing the whole preferences decode.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = JobSort(rawValue: raw) ?? .best
    }
}

/// Where the work happens. Mirrors the API's `work_arrangement` values; a
/// posting that doesn't say has an empty string there and matches none of these.
public enum Workplace: String, Codable, CaseIterable, Identifiable, Sendable {
    case remote
    case hybrid
    case onsite

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .remote: return "Remote"
        case .hybrid: return "Hybrid"
        case .onsite: return "On-site"
        }
    }

    public var systemImage: String {
        switch self {
        case .remote: return "house"
        case .hybrid: return "arrow.left.arrow.right"
        case .onsite: return "building.2"
        }
    }
}

/// Which optional Job-Feed filters an account wants surfaced, and the settings
/// they run on. Mirrors the API's `api/identity/filter-preferences/` shape. The
/// client decodes with `.convertFromSnakeCase` and encodes with
/// `.convertToSnakeCase`, so property names stay camelCase here and map to
/// `job_type` / `home_latitude` / … on the wire.
public struct JobFilterPreferences: Codable, Equatable, Sendable {
    public var salary: Bool
    /// The Workplace filter (remote / hybrid / on-site). Named for the
    /// remote-only toggle it replaced, so the server field is unchanged.
    public var remote: Bool
    public var distance: Bool
    public var postedDate: Bool
    public var jobType: Bool
    public var matchScore: Bool
    /// "No account needed": hides postings whose portal wants an account first.
    public var easyApply: Bool

    /// Where distances are measured from. Geocoded on the device from what she
    /// typed; the label is only for showing it back.
    public var homeLabel: String
    public var homeLatitude: Double?
    public var homeLongitude: Double?
    /// The last radius chosen, so the distance filter reopens where she left it.
    public var radiusMiles: Int
    /// The last sort chosen.
    public var sort: JobSort

    public init(salary: Bool = true, remote: Bool = true, distance: Bool = true,
                postedDate: Bool = true, jobType: Bool = false, matchScore: Bool = false,
                easyApply: Bool = false, homeLabel: String = "", homeLatitude: Double? = nil,
                homeLongitude: Double? = nil, radiusMiles: Int = 25, sort: JobSort = .best) {
        self.salary = salary
        self.remote = remote
        self.distance = distance
        self.postedDate = postedDate
        self.jobType = jobType
        self.matchScore = matchScore
        self.easyApply = easyApply
        self.homeLabel = homeLabel
        self.homeLatitude = homeLatitude
        self.homeLongitude = homeLongitude
        self.radiusMiles = radiusMiles
        self.sort = sort
    }

    enum CodingKeys: String, CodingKey {
        case salary, remote, distance, postedDate, jobType, matchScore, easyApply
        case homeLabel, homeLatitude, homeLongitude, radiusMiles, sort
    }

    /// Lenient decode: an older or newer server row might omit a key this client
    /// doesn't share, and a missing setting should take its default rather than
    /// fail the whole decode.
    public init(from decoder: Decoder) throws {
        let defaults = JobFilterPreferences()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys, _ fallback: Bool) throws -> Bool {
            try container.decodeIfPresent(Bool.self, forKey: key) ?? fallback
        }
        salary = try flag(.salary, defaults.salary)
        remote = try flag(.remote, defaults.remote)
        distance = try flag(.distance, defaults.distance)
        postedDate = try flag(.postedDate, defaults.postedDate)
        jobType = try flag(.jobType, defaults.jobType)
        matchScore = try flag(.matchScore, defaults.matchScore)
        easyApply = try flag(.easyApply, defaults.easyApply)
        homeLabel = try container.decodeIfPresent(String.self, forKey: .homeLabel) ?? ""
        homeLatitude = try container.decodeIfPresent(Double.self, forKey: .homeLatitude)
        homeLongitude = try container.decodeIfPresent(Double.self, forKey: .homeLongitude)
        radiusMiles = try container.decodeIfPresent(Int.self, forKey: .radiusMiles) ?? defaults.radiusMiles
        sort = try container.decodeIfPresent(JobSort.self, forKey: .sort) ?? defaults.sort
    }

    /// The coordinates are always written, as null when cleared — the
    /// synthesized encoder would skip a nil, and the server would keep the old home.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(salary, forKey: .salary)
        try container.encode(remote, forKey: .remote)
        try container.encode(distance, forKey: .distance)
        try container.encode(postedDate, forKey: .postedDate)
        try container.encode(jobType, forKey: .jobType)
        try container.encode(matchScore, forKey: .matchScore)
        try container.encode(easyApply, forKey: .easyApply)
        try container.encode(homeLabel, forKey: .homeLabel)
        if let homeLatitude, let homeLongitude {
            try container.encode(homeLatitude, forKey: .homeLatitude)
            try container.encode(homeLongitude, forKey: .homeLongitude)
        } else {
            try container.encodeNil(forKey: .homeLatitude)
            try container.encodeNil(forKey: .homeLongitude)
        }
        try container.encode(radiusMiles, forKey: .radiusMiles)
        try container.encode(sort, forKey: .sort)
    }

    /// True once a home location is saved, which distance filtering and the
    /// "Closest" sort both need.
    public var hasHome: Bool { homeLatitude != nil && homeLongitude != nil }

    /// True when the user has hidden every filter — the feed shows only sort
    /// and search.
    public var isNoneEnabled: Bool {
        !(salary || remote || distance || postedDate || jobType || matchScore || easyApply)
    }
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
    /// Any of these arrangements; empty means all, including postings that
    /// don't say.
    public var workplaces: [Workplace]
    /// Straight-line miles from the saved home. Needs a home on the server;
    /// without one the server ignores it.
    public var withinMiles: Int?
    /// Keep remote jobs when a radius is set — they're within reach of anywhere.
    public var includeRemoteInRadius: Bool
    /// Listed in the last N days.
    public var postedWithinDays: Int?
    /// Normalized job-type tokens, e.g. "full_time", "contract".
    public var jobTypes: [String]
    /// Minimum fit score, 0–100.
    public var minScore: Int?
    /// Hide postings whose portal wants an account before showing the form.
    public var noAccountOnly: Bool
    /// Words that must all appear in the title, company or description.
    public var search: String
    /// Ordering, not a filter: never counted by `isEmpty`.
    public var sort: JobSort

    public init(salaryMin: Int? = nil, salaryMax: Int? = nil,
                includeUnspecifiedSalary: Bool = true,
                workplaces: [Workplace] = [], withinMiles: Int? = nil,
                includeRemoteInRadius: Bool = true, postedWithinDays: Int? = nil,
                jobTypes: [String] = [], minScore: Int? = nil,
                noAccountOnly: Bool = false, search: String = "", sort: JobSort = .best) {
        self.salaryMin = salaryMin
        self.salaryMax = salaryMax
        self.includeUnspecifiedSalary = includeUnspecifiedSalary
        self.workplaces = workplaces
        self.withinMiles = withinMiles
        self.includeRemoteInRadius = includeRemoteInRadius
        self.postedWithinDays = postedWithinDays
        self.jobTypes = jobTypes
        self.minScore = minScore
        self.noAccountOnly = noAccountOnly
        self.search = search
        self.sort = sort
    }

    private var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when nothing here actually constrains the feed. Sort doesn't count.
    public var isEmpty: Bool {
        salaryMin == nil && salaryMax == nil && workplaces.isEmpty && withinMiles == nil
            && postedWithinDays == nil && jobTypes.isEmpty && minScore == nil
            && !noAccountOnly && trimmedSearch.isEmpty
    }

    /// The same query with every filter cleared but the sort kept.
    public var cleared: JobFilterQuery { JobFilterQuery(sort: sort) }

    public var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let salaryMin { items.append(URLQueryItem(name: "salary_min", value: String(salaryMin))) }
        if let salaryMax { items.append(URLQueryItem(name: "salary_max", value: String(salaryMax))) }
        // The flag only means anything when a salary bound is set.
        if (salaryMin != nil || salaryMax != nil) && !includeUnspecifiedSalary {
            items.append(URLQueryItem(name: "include_unspecified_salary", value: "0"))
        }
        for workplace in workplaces {
            items.append(URLQueryItem(name: "workplace", value: workplace.rawValue))
        }
        if let withinMiles {
            items.append(URLQueryItem(name: "within_miles", value: String(withinMiles)))
            if !includeRemoteInRadius {
                items.append(URLQueryItem(name: "include_remote", value: "0"))
            }
        }
        if let postedWithinDays {
            items.append(URLQueryItem(name: "posted_within", value: String(postedWithinDays)))
        }
        for type in jobTypes {
            items.append(URLQueryItem(name: "job_type", value: type))
        }
        if let minScore { items.append(URLQueryItem(name: "min_score", value: String(minScore))) }
        if noAccountOnly { items.append(URLQueryItem(name: "no_account", value: "1")) }
        if !trimmedSearch.isEmpty { items.append(URLQueryItem(name: "q", value: trimmedSearch)) }
        if sort != .best { items.append(URLQueryItem(name: "sort", value: sort.rawValue)) }
        return items
    }
}
