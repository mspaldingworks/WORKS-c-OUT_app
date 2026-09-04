import Foundation
import Testing
@testable import WorksCoutCore

struct DecodingTests {
    /// A real response captured from the Django backend (see Famiy_Appily_api's
    /// tracker/serializers.py) — guards against the snake_case/date-format
    /// assumptions baked into WorksCoutAPIClient's decoder configuration.
    @Test func decodesApplicationFromDjangoPayload() throws {
        let json = """
        {
            "id": 1, "company": 1, "company_name": "Acme Corp", "role_title": "Staff Engineer",
            "job_url": "https://example.com/job/1", "status": "saved", "source": "ingested",
            "applied_date": null, "salary_notes": "", "resume": null, "cover_letter": null,
            "notes": "Promoted from ingested posting.",
            "created_at": "2026-08-31T20:04:47.073558Z", "updated_at": "2026-08-31T20:04:47.073558Z",
            "events": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad date")
            }
            return date
        }

        let application = try decoder.decode(Application.self, from: json)
        #expect(application.companyName == "Acme Corp")
        #expect(application.roleTitle == "Staff Engineer")
        #expect(application.status == .saved)
        #expect(application.source == .ingested)
        #expect(application.appliedDate == nil)
    }

    /// Guards the URL construction in `request(_:method:queryItems:body:)`.
    /// Appending "?status=new" to the path instead of using URLComponents would
    /// percent-encode the "?" into %3F and silently 404.
    @Test func queryItemsProduceAValidURLRatherThanAnEncodedPath() throws {
        let base = URL(string: "https://jobs.family-appily.com")!
        var components = URLComponents(
            url: base.appendingPathComponent("api/ingestion/postings/"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "status", value: "new")]
        let url = try #require(components?.url)

        #expect(url.absoluteString == "https://jobs.family-appily.com/api/ingestion/postings/?status=new")
        #expect(!url.absoluteString.contains("%3F"))
    }

    @Test func newApplicationEncodesToSnakeCase() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let payload = NewApplication(company: 1, roleTitle: "Staff Engineer", jobUrl: "https://example.com")
        let data = try encoder.encode(payload)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["role_title"] as? String == "Staff Engineer")
        #expect(object["job_url"] as? String == "https://example.com")
    }
}

struct MaterialsDecodingTests {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad date")
            }
            return date
        }
        return decoder
    }

    private func application(materials: String) -> Data {
        """
        {
            "id": 1, "company": 1, "company_name": "Acme Corp", "role_title": "Staff Engineer",
            "job_url": "https://example.com/job/1", "apply_url": "https://example.com/apply",
            "generated_materials": \(materials),
            "resume_drive_url": "", "cover_letter_drive_url": "",
            "status": "ready", "source": "ingested",
            "applied_date": null, "salary_notes": "", "resume": null, "cover_letter": null,
            "notes": "", "created_at": "2026-09-02T12:52:22.054202Z",
            "updated_at": "2026-09-02T12:52:22.054209Z", "events": []
        }
        """.data(using: .utf8)!
    }

    /// The bug that emptied the Drafts screen: one legacy application with no
    /// linked posting serialised its materials as `{}`, and the strict
    /// synthesised initialiser threw on the missing keys — failing the decode
    /// of every other application in the same response.
    @Test func decodesAnEmptyMaterialsObjectWithoutThrowing() throws {
        let decoded = try decoder().decode(Application.self, from: application(materials: "{}"))
        #expect(decoded.generatedMaterials?.isEmpty == true)
        #expect(decoded.generatedMaterials?.coverLetter == "")
    }

    @Test func decodesNullMaterials() throws {
        let decoded = try decoder().decode(Application.self, from: application(materials: "null"))
        #expect(decoded.generatedMaterials == nil)
    }

    @Test func decodesPartialMaterials() throws {
        let decoded = try decoder().decode(
            Application.self,
            from: application(materials: #"{"cover_letter": "Dear Hiring Team"}"#))
        #expect(decoded.generatedMaterials?.coverLetter == "Dear Hiring Team")
        #expect(decoded.generatedMaterials?.gaps.isEmpty == true)
    }

    @Test func decodesFullMaterials() throws {
        let json = #"""
        {"cover_letter": "Dear Hiring Team", "resume_summary": "Development leader.",
         "resume_bullets": ["Grew Give for Good"], "gaps": ["No PMP."], "unparsed": false}
        """#
        let decoded = try decoder().decode(Application.self, from: application(materials: json))
        let materials = try #require(decoded.generatedMaterials)
        #expect(materials.resumeBullets == ["Grew Give for Good"])
        #expect(materials.gaps == ["No PMP."])
        #expect(materials.isEmpty == false)
    }

    /// One bad row must not take the rest of the list with it.
    @Test func oneMalformedRowDoesNotFailTheWholeList() throws {
        let list = """
        [\(String(data: application(materials: "{}"), encoding: .utf8)!),
         \(String(data: application(materials: #"{"cover_letter": "Real letter"}"#), encoding: .utf8)!)]
        """.data(using: .utf8)!
        let decoded = try decoder().decode([Application].self, from: list)
        #expect(decoded.count == 2)
        #expect(decoded[1].generatedMaterials?.coverLetter == "Real letter")
    }
}

struct PostingDetailsDecodingTests {
    private func decode(_ json: String) throws -> PostingDetails {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PostingDetails.self, from: json.data(using: .utf8)!)
    }

    /// Shape captured from the live API (ingestion/details.py).
    @Test func decodesTheRealDetailsShape() throws {
        let details = try decode("""
        {"description": "Lead our digital fundraising.", "location": "Carlsbad, CA",
         "salary": "$70,000 - $80,000 a year", "job_types": ["Full-time", "Remote"],
         "benefits": ["Health insurance"], "requirements": [], "shifts": [],
         "posted": "3 hours ago", "is_remote": true, "company_rating": "2.8 from 10 reviews"}
        """)
        #expect(details.salary == "$70,000 - $80,000 a year")
        #expect(details.jobTypes == ["Full-time", "Remote"])
        #expect(details.isRemote)
        #expect(details.hasAnything)
    }

    /// Scrapers omit plenty, so every field defaults rather than throwing —
    /// one sparse posting must not empty the whole feed.
    @Test func decodesASparsePayload() throws {
        let details = try decode("{}")
        #expect(details.description == "")
        #expect(details.jobTypes.isEmpty)
        #expect(details.hasAnything == false)
    }

    @Test func summaryChipsDoNotRepeatRemoteTwice() throws {
        let details = try decode("""
        {"location": "Remote", "is_remote": true, "job_types": ["Remote", "Full-time"],
         "salary": "", "description": "x", "benefits": [], "requirements": [],
         "shifts": [], "posted": "", "company_rating": ""}
        """)
        #expect(details.summaryChips.filter { $0 == "Remote" }.count == 1)
        #expect(details.summaryChips.contains("Full-time"))
    }
}

struct PostingSkillsDecodingTests {
    private func decode(_ json: String) throws -> PostingSkills {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PostingSkills.self, from: json.data(using: .utf8)!)
    }

    @Test func decodesBothLists() throws {
        let skills = try decode(#"{"matched": ["Fundraising", "WordPress"], "missing": ["Tableau"]}"#)
        #expect(skills.matched.count == 2)
        #expect(skills.missing == ["Tableau"])
        #expect(skills.hasAnything)
    }

    /// A posting with no description yields neither list; the card should just
    /// omit the pills rather than fail to decode.
    @Test func decodesAnEmptyResult() throws {
        let skills = try decode("{}")
        #expect(skills.matched.isEmpty)
        #expect(skills.hasAnything == false)
    }
}
