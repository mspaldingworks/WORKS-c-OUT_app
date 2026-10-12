import Foundation
import Testing
@testable import WorksCoutCore

/// Answers requests from a canned table instead of the network, keyed by host
/// so tests running side by side don't see each other's answers.
final class StubProtocol: URLProtocol {
    struct Answer {
        var status: Int
        var body: String
    }

    private static let lock = NSLock()
    private static var answers: [String: Answer] = [:]
    private static var seen: [String: URLRequest] = [:]

    static func answer(host: String, status: Int, body: String) {
        lock.withLock { answers[host] = Answer(status: status, body: body) }
    }

    static func request(to host: String) -> URLRequest? {
        lock.withLock { seen[host] }
    }

    static func client(host: String, token: String) -> WorksCoutAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return WorksCoutAPIClient(
            configuration: .init(baseURL: URL(string: "https://\(host)")!, token: token),
            session: URLSession(configuration: configuration)
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let host = request.url?.host ?? ""
        let answer = Self.lock.withLock {
            Self.seen[host] = request
            return Self.answers[host] ?? Answer(status: 500, body: "")
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

struct AccountTests {
    private static let session = #"{"token": "abc123", "email": "new@example.test", "username": "new@example.test"}"#

    /// Signed out there is no token, and the server rejects a bare "Token "
    /// header with a 401 before it ever looks at the email and password.
    @Test func signingInSendsNoAuthorizationHeader() async throws {
        let host = "sign-in.test"
        StubProtocol.answer(host: host, status: 200, body: Self.session)

        let signedIn = try await StubProtocol.client(host: host, token: "")
            .signIn(email: "new@example.test", password: "pw")

        let sent = try #require(StubProtocol.request(to: host))
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.httpMethod == "POST")
        #expect(sent.url?.absoluteString == "https://sign-in.test/api/identity/auth/sign-in/")
        #expect(signedIn.token == "abc123")
        #expect(signedIn.account.displayName == "new@example.test")
    }

    @Test func signingUpPostsToItsOwnRoute() async throws {
        let host = "sign-up.test"
        StubProtocol.answer(host: host, status: 201, body: Self.session)

        _ = try await StubProtocol.client(host: host, token: "")
            .signUp(email: "new@example.test", password: "pw")

        #expect(StubProtocol.request(to: host)?.url?.absoluteString == "https://sign-up.test/api/identity/auth/sign-up/")
    }

    @Test func aSignedInClientSendsItsToken() async throws {
        let host = "me.test"
        StubProtocol.answer(host: host, status: 200, body: #"{"email": "", "username": "madelyn"}"#)

        let account = try await StubProtocol.client(host: host, token: "abc123").fetchAccount()

        #expect(StubProtocol.request(to: host)?.value(forHTTPHeaderField: "Authorization") == "Token abc123")
        // The owner's older account may have no email on it.
        #expect(account.displayName == "madelyn")
        // A server that doesn't say predates the bring-your-own-key rule.
        #expect(account.usesServerAIKey)
    }

    @Test func anAccountMadeInTheAppIsToldToBringItsOwnKey() async throws {
        let host = "self-made.test"
        StubProtocol.answer(host: host, status: 200,
                            body: #"{"email": "new@example.test", "username": "new@example.test", "uses_server_ai_key": false}"#)

        let account = try await StubProtocol.client(host: host, token: "abc123").fetchAccount()

        #expect(account.usesServerAIKey == false)
    }

    /// The server's own wording reaches the sign-in screen, whichever field it
    /// was about.
    @Test func aRefusalCarriesTheServersReason() async {
        let host = "refused.test"
        StubProtocol.answer(host: host, status: 400,
                            body: #"{"non_field_errors": ["That email and password don't match an account."]}"#)

        await #expect(throws: WorksCoutAPIError.badRequest("That email and password don't match an account.")) {
            _ = try await StubProtocol.client(host: host, token: "").signIn(email: "a@b.test", password: "x")
        }
    }

    @Test func beingThrottledIsItsOwnError() async {
        let host = "throttled.test"
        StubProtocol.answer(host: host, status: 429, body: #"{"detail": "Request was throttled."}"#)

        await #expect(throws: WorksCoutAPIError.tooManyAttempts) {
            _ = try await StubProtocol.client(host: host, token: "").signIn(email: "a@b.test", password: "x")
        }
    }
}
