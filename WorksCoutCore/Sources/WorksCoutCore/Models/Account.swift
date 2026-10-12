import Foundation

/// Which account a token belongs to, as `api/identity/auth/me/` reports it.
public struct Account: Codable, Equatable, Sendable {
    public var email: String
    public var username: String
    /// False for an account made through sign-up: it has to add its own AI
    /// key in Identity before résumés can be read or drafts written.
    public var usesServerAIKey: Bool

    public init(email: String = "", username: String = "", usesServerAIKey: Bool = true) {
        self.email = email
        self.username = username
        self.usesServerAIKey = usesServerAIKey
    }

    /// The client decodes with `.convertFromSnakeCase`, which turns
    /// `uses_server_ai_key` into "usesServerAiKey" — lowercase "i".
    enum CodingKeys: String, CodingKey {
        case email, username
        case usesServerAIKey = "usesServerAiKey"
    }

    /// Lenient: a server that doesn't say is one that predates the rule.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        usesServerAIKey = try container.decodeIfPresent(Bool.self, forKey: .usesServerAIKey) ?? true
    }

    /// What to show for "signed in as". An account made in the app has an
    /// email; the owner's older account may only have a username.
    public var displayName: String {
        email.isEmpty ? username : email
    }
}

/// What signing in or signing up returns: the account, and the token every
/// later request is made with.
public struct AccountSession: Codable, Equatable, Sendable {
    public var token: String
    public var email: String
    public var username: String

    public var account: Account { Account(email: email, username: username) }
}

/// The body of both sign-in and sign-up.
struct AccountCredentials: Encodable, Sendable {
    var email: String
    var password: String
}
