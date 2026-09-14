import AuthenticationServices
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Runs one `ASWebAuthenticationSession` (OAuth consent) and returns the final
/// callback URL. Cross-platform (iOS + macOS). Returns nil when the user cancels.
///
/// No Info.plist URL scheme is needed: `callbackURLScheme` is captured by the
/// session itself, not registered system-wide.
final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    @MainActor
    func authenticate(url: URL, callbackScheme: String) async throws -> URL? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL?, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    // A user closing the sheet isn't an error worth surfacing.
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                } else {
                    continuation.resume(returning: callbackURL)
                }
            }
            session.presentationContextProvider = self
            // Reuse the user's existing Google login rather than a cookie-less session.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: URLError(.cannotConnectToHost))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(iOS)
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            return window ?? ASPresentationAnchor()
            #else
            return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
            #endif
        }
    }
}
