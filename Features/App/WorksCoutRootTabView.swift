import WorksCoutCore
import SwiftUI

/// Root of the app. With an account in use it opens straight to the Job Feed;
/// her own builds have her token baked in (see WorksCoutConfig), so for her
/// there is still no gate. Signed out, the sign-in screen takes the place of
/// the sections. Signing out lives at the bottom of Identity.
public struct WorksCoutRootTabView: View {
    @State private var session = WorksCoutSessionModel()
    @State private var selectedSection = Section.jobFeed
    // The server stopped accepting the token mid-session: offer sign-in over
    // whatever is on screen rather than throwing it away.
    @State private var isSigningIn = false

    enum Section: String, CaseIterable, Identifiable {
        case jobFeed = "Job Feed"
        case drafts = "Drafts"
        case approvals = "Approvals"
        case applied = "Applied"
        case identity = "Identity"
        var id: String { rawValue }
    }

    public init() {}

    public var body: some View {
        Group {
            if session.isSignedIn {
                sections
                    // A different account means different everything: rebuild
                    // rather than leave the last account's rows on screen.
                    .id(session.generation)
            } else {
                WorksCoutSignInView(session: session)
            }
        }
        .tint(Brand.accent)
        .onChange(of: session.generation) { selectedSection = .jobFeed }
        .sheet(isPresented: $isSigningIn) {
            NavigationStack {
                WorksCoutSignInView(session: session) { isSigningIn = false }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isSigningIn = false }
                        }
                    }
            }
            .tint(Brand.accent)
        }
    }

    private var sections: some View {
        let client = session.client
        return NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedSection) {
                    ForEach(Section.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                BrandRule()

                switch selectedSection {
                case .jobFeed:
                    JobFeedView(client: client, onUnauthorized: { isSigningIn = true })
                case .drafts:
                    DraftsView(client: client, onUnauthorized: { isSigningIn = true })
                case .approvals:
                    ApprovalsView(client: client, onUnauthorized: { isSigningIn = true })
                case .applied:
                    AppliedView(client: client, onUnauthorized: { isSigningIn = true })
                case .identity:
                    IdentityView(client: client, onUnauthorized: { isSigningIn = true },
                                 onSignOut: { session.signOut() })
                }
            }
            .navigationTitle("Job Search")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        BrandMark(size: 26)
                        BrandWordmark(height: 20)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("WORKS(c)OUT")
                    .accessibilityAddTraits(.isHeader)
                }
            }
        }
    }
}
