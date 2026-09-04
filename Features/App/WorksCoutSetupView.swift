import SwiftUI

/// One-time API token entry — shared by both the iOS tab and the Mac app's
/// root view. Not a login screen: just a Keychain-backed token paste, since
/// Family Appily has no accounts anywhere.
struct WorksCoutSetupView: View {
    let onSave: (String) -> Void

    /// Prefilled from the build-time token when there is one, so this screen is
    /// a single tap rather than a "what do I put here?" dead end. It should
    /// rarely appear at all — it's the fallback when no token is compiled in,
    /// or after a stored token was rejected.
    @State private var token = WorksCoutConfig.buildTimeToken ?? ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 48))
                .accessibilityHidden(true)
            Text("Connect Job Search")
                .font(.title2.weight(.semibold))
            Text("Enter the API token generated for this device. This is a one-time setup, not an account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            SecureField("API token", text: $token)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            Button("Save") { onSave(token) }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .disabled(token.isEmpty)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
