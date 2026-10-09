import Foundation
import Testing
@testable import WorksCoutCore

struct JobFilterPreferencesCodingTests {
    private func decode(_ json: String) throws -> JobFilterPreferences {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(JobFilterPreferences.self, from: Data(json.utf8))
    }

    private func encode(_ preferences: JobFilterPreferences) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(preferences)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func decodesTheFullServerShape() throws {
        let prefs = try decode("""
        {"salary": true, "remote": true, "distance": true, "posted_date": false,
         "job_type": false, "match_score": true, "easy_apply": true,
         "home_label": "Louisville, KY 40205", "home_latitude": 38.22, "home_longitude": -85.69,
         "radius_miles": 40, "sort": "closest", "updated_at": "2026-10-09T12:00:00Z"}
        """)
        #expect(prefs.distance)
        #expect(!prefs.postedDate)
        #expect(prefs.easyApply)
        #expect(prefs.homeLabel == "Louisville, KY 40205")
        #expect(prefs.hasHome)
        #expect(prefs.radiusMiles == 40)
        #expect(prefs.sort == .closest)
    }

    @Test func anOlderServerRowTakesDefaults() throws {
        let prefs = try decode(#"{"salary": false, "remote": false, "job_type": true, "match_score": false}"#)
        #expect(!prefs.salary)
        #expect(prefs.distance)
        #expect(prefs.postedDate)
        #expect(!prefs.hasHome)
        #expect(prefs.radiusMiles == 25)
        #expect(prefs.sort == .best)
    }

    @Test func anUnknownSortFallsBackToBestMatch() throws {
        #expect(try decode(#"{"sort": "vibes"}"#).sort == .best)
    }

    @Test func clearingHomeSendsNullsSoTheServerForgetsIt() throws {
        let body = try encode(JobFilterPreferences())
        #expect(body["home_latitude"] is NSNull)
        #expect(body["home_longitude"] is NSNull)
        #expect(body["posted_date"] as? Bool == true)
        #expect(body["easy_apply"] as? Bool == false)
    }

    @Test func aSetHomeIsSent() throws {
        let body = try encode(JobFilterPreferences(homeLatitude: 38.2, homeLongitude: -85.7))
        #expect(body["home_latitude"] as? Double == 38.2)
        #expect(body["home_longitude"] as? Double == -85.7)
    }
}

struct JobFilterQueryTests {
    private func params(_ query: JobFilterQuery) -> [String] {
        query.queryItems.map { "\($0.name)=\($0.value ?? "")" }
    }

    @Test func emptyQuerySendsNothing() {
        #expect(JobFilterQuery().isEmpty)
        #expect(JobFilterQuery().queryItems.isEmpty)
    }

    @Test func sortIsNotAFilter() {
        let query = JobFilterQuery(sort: .pay)
        #expect(query.isEmpty)
        #expect(params(query) == ["sort=pay"])
    }

    @Test func workplacesDistanceDateAndAccount() {
        let query = JobFilterQuery(workplaces: [.remote, .hybrid], withinMiles: 25,
                                   includeRemoteInRadius: false, postedWithinDays: 7,
                                   noAccountOnly: true)
        #expect(!query.isEmpty)
        #expect(params(query) == [
            "workplace=remote", "workplace=hybrid", "within_miles=25", "include_remote=0",
            "posted_within=7", "no_account=1",
        ])
    }

    @Test func includeRemoteIsOnlySentWithARadius() {
        #expect(params(JobFilterQuery(includeRemoteInRadius: false)).isEmpty)
    }

    @Test func searchIsTrimmedAndBlankSearchIsNoFilter() {
        #expect(JobFilterQuery(search: "   ").isEmpty)
        #expect(params(JobFilterQuery(search: "  grant writer ")) == ["q=grant writer"])
    }

    @Test func clearingKeepsTheSort() {
        let query = JobFilterQuery(workplaces: [.onsite], search: "x", sort: .newest)
        #expect(query.cleared == JobFilterQuery(sort: .newest))
    }
}

struct PostingPlacementTests {
    private func posting(_ extra: String) throws -> IngestedPosting {
        let json = """
        {"id": 1, "source": "apify:indeed", "title": "Program Manager", "company_name": "Acme",
         "url": "https://x.test/1", "apply_url": "", "status": "new", "score": 80,
         "score_reasons": [], "platform": "", "requires_account": false, "sign_in_url": "",
         "details": {"location": "Louisville, KY", "is_remote": true, "salary": "$70,000 a year"},
         "created_at": "2026-10-01T12:00:00Z"\(extra)}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IngestedPosting.self, from: Data(json.utf8))
    }

    @Test func decodesWithoutTheNewFields() throws {
        let row = try posting("")
        #expect(row.workplace == nil)
        #expect(row.distanceMiles == nil)
        #expect(row.cardChips == ["Remote", "Louisville, KY", "$70,000 a year"])
    }

    @Test func hybridReplacesTheBoardsRemoteFlagAndShowsDistance() throws {
        let row = try posting(#", "work_arrangement": "hybrid", "posted_at": "2026-09-30", "distance_miles": 12.4"#)
        #expect(row.workplace == .hybrid)
        #expect(row.postedAt == "2026-09-30")
        #expect(row.cardChips == ["Hybrid", "12 mi away", "Louisville, KY", "$70,000 a year"])
    }

    @Test func unknownArrangementIsNil() throws {
        #expect(try posting(#", "work_arrangement": """#).workplace == nil)
    }

    @Test func distancesRoundTheWayPeopleSayThem() throws {
        let far = try posting(#", "distance_miles": 12.6"#)
        let close = try posting(#", "distance_miles": 0.4"#)
        #expect(far.distanceLabel == "13 mi away")
        #expect(close.distanceLabel == "Under 1 mi away")
    }
}
