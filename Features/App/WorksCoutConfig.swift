import Foundation
import WorksCoutCore
import OSLog
import Security

private let logger = Logger(subsystem: "com.mspaldingworks.WorksCout", category: "JobSearch")

/// Keychain-backed storage for the WORKS(c)OUT API token. There's no login
/// screen — the token is provisioned once and then just sits in the Keychain.
/// It identifies a real account server-side (every row has an owner), there
/// is simply only one of them, so a login form would be a wall with nothing
/// behind it.
enum WorksCoutKeychain {
    private static let service = "com.mspaldingworks.WorksCout.token"
    private static let tokenAccount = "api-token"

    static func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clearToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum WorksCoutConfig {
    /// WORKS(c)OUT's own domain. The old jobs.family-appily.com pointed at the
    /// pre-split deployment, which shared a container and database with the
    /// household app — this one shares nothing with it.
    static let baseURL = URL(string: "https://api.workscout.agency")!

    /// A token baked in at build time via `JOB_SEARCH_API_TOKEN=...` on the
    /// xcodebuild command line, so a fresh install just works instead of asking
    /// for a 40-character paste on a phone keyboard. Nothing secret is stored in
    /// the repo — without the build setting this is empty and the app falls back
    /// to the manual setup screen.
    static var buildTimeToken: String? {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "WorksCoutAPIToken") as? String,
              !token.isEmpty,
              !token.hasPrefix("$(") // unsubstituted placeholder
        else { return nil }
        return token
    }

    /// The compiled-in token wins, and the keychain is only consulted when
    /// there isn't one.
    ///
    /// This order exists for macOS. Reading the login keychain there prompts
    /// for the account password, and when the token is already baked into the
    /// build that prompt buys nothing — it's a password dialog guarding a
    /// lookup certain to come back empty. iOS never showed it, so the cost was
    /// invisible until the app ran on a Mac.
    static var resolvedToken: String? {
        if let baked = buildTimeToken { return baked }
        let stored = WorksCoutKeychain.loadToken()
        return stored?.isEmpty == false ? stored : nil
    }

    /// Always returns a client, even with no token. The Job Feed is the whole
    /// point of this tab and must open straight to the list — a missing token
    /// is an error to show inside the feed, not a wall in front of it.
    static func makeClient() -> WorksCoutAPIClient {
        // Resolve once. The old version read the keychain here and again in
        // resolvedToken, so a single launch could raise two password prompts.
        let token = resolvedToken
        // Never logs the token itself — just which source won, which is the only
        // thing needed to diagnose "why is it asking me to connect again?".
        logger.debug("""
            token source: \(buildTimeToken != nil ? "build-time" : (token != nil ? "keychain" : "none"), privacy: .public)
            """)
        return WorksCoutAPIClient(configuration: .init(baseURL: baseURL, token: token ?? ""))
    }
}
