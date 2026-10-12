import Foundation
import Observation
import WorksCoutCore
import OSLog
import Security

private let logger = Logger(subsystem: "com.mspaldingworks.WorksCout", category: "JobSearch")

/// Keychain-backed storage for the token of the account signed in on this
/// device (see WorksCoutSession). The token compiled into a build never goes
/// in here; it is read straight from the bundle.
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

/// Which account this device is using, and where its token comes from.
///
/// Kept in UserDefaults, apart from the token itself, for two reasons. Signing
/// out has to outlast a relaunch even though a compiled-in token is still
/// sitting in the bundle. And it lets a build that uses its compiled-in token
/// skip the Keychain entirely (see `WorksCoutConfig.resolvedToken`).
enum WorksCoutSession {
    enum Source: String {
        /// The token compiled into this build. The starting state, and what
        /// every install was before accounts could be switched.
        case builtIn
        /// An account signed in to (or made) on this device; token in the Keychain.
        case signedIn
        case signedOut
    }

    private static let sourceKey = "WorksCoutAccountSource"

    static var source: Source {
        get { UserDefaults.standard.string(forKey: sourceKey).flatMap(Source.init(rawValue:)) ?? .builtIn }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sourceKey) }
    }

    static func signIn(token: String) {
        WorksCoutKeychain.saveToken(token)
        source = .signedIn
    }

    /// Forgets the account on this device only. Nothing is revoked or deleted
    /// server-side, so the same account still works on another device and can
    /// be signed back in to here.
    static func signOut() {
        WorksCoutKeychain.clearToken()
        source = .signedOut
    }

    /// Back to the token compiled into this build.
    static func useBuiltInAccount() {
        WorksCoutKeychain.clearToken()
        source = .builtIn
    }
}

enum WorksCoutConfig {
    /// WORKS(c)OUT's own domain. The old jobs.family-appily.com pointed at the
    /// pre-split deployment, which shared a container and database with the
    /// household app — this one shares nothing with it.
    static let baseURL = URL(string: "https://api.workscout.agency")!

    /// A token baked in at build time (`WORKS_COUT_API_TOKEN` in the gitignored
    /// Local.xcconfig), so her own install opens straight to her account.
    /// Nothing secret is stored in the repo — without the build setting this is
    /// empty and the app opens on the sign-in screen.
    static var buildTimeToken: String? {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "WorksCoutAPIToken") as? String,
              !token.isEmpty,
              !token.hasPrefix("$(") // unsubstituted placeholder
        else { return nil }
        return token
    }

    /// The token for whichever account this device is using, or nil when
    /// signed out.
    ///
    /// While the build's own account is in use, the compiled-in token wins and
    /// the keychain is only consulted when there isn't one. That order exists
    /// for macOS. Reading the login keychain there prompts for the account
    /// password, and when the token is already baked into the build that
    /// prompt buys nothing — it's a password dialog guarding a lookup certain
    /// to come back empty. iOS never showed it, so the cost was invisible
    /// until the app ran on a Mac. The keychain is read first only once
    /// someone has actually signed in to an account on this device.
    static var resolvedToken: String? {
        switch WorksCoutSession.source {
        case .signedOut:
            return nil
        case .signedIn:
            return storedToken
        case .builtIn:
            // The keychain fallback is for a build with no compiled-in token
            // that had one pasted in before there was a sign-in screen.
            return buildTimeToken ?? storedToken
        }
    }

    private static var storedToken: String? {
        let stored = WorksCoutKeychain.loadToken()
        return stored?.isEmpty == false ? stored : nil
    }

    /// A client for `token`; empty means signed out, which can still reach
    /// sign-in and sign-up. Never logs the token itself.
    static func makeClient(token: String?) -> WorksCoutAPIClient {
        WorksCoutAPIClient(configuration: .init(baseURL: baseURL, token: token ?? ""))
    }
}

/// The account in use, as the views see it. One of these lives at the root of
/// each platform's app; signing in or out swaps the client and bumps
/// `generation`, which the root uses to rebuild every section so nothing
/// loaded for the previous account stays on screen.
@MainActor
@Observable
final class WorksCoutSessionModel {
    private(set) var client: WorksCoutAPIClient
    private(set) var isSignedIn: Bool
    private(set) var generation = 0

    init() {
        // Resolve once: on a Mac each keychain read can raise a password prompt.
        let token = WorksCoutConfig.resolvedToken
        client = WorksCoutConfig.makeClient(token: token)
        isSignedIn = token != nil
        // Only which source won — the thing needed to diagnose "why is it
        // asking me to sign in again?".
        logger.debug("account source: \(WorksCoutSession.source.rawValue, privacy: .public), token found: \(token != nil, privacy: .public)")
    }

    func signIn(_ session: AccountSession) {
        WorksCoutSession.signIn(token: session.token)
        use(token: session.token)
    }

    func signOut() {
        WorksCoutSession.signOut()
        use(token: nil)
    }

    /// Only offered when this build has a token compiled in.
    func useBuiltInAccount() {
        guard let token = WorksCoutConfig.buildTimeToken else { return }
        WorksCoutSession.useBuiltInAccount()
        use(token: token)
    }

    private func use(token: String?) {
        client = WorksCoutConfig.makeClient(token: token)
        isSignedIn = token != nil
        generation += 1
    }
}
