import SwiftUI
import WorksCoutCore

/// Sidebar + detail on the Mac, same pipeline order as the phone. Signed out,
/// the sign-in screen takes the window; signing out lives at the bottom of
/// Identity, as on the phone.
struct WorksCoutMacRootView: View {
    @State private var session = WorksCoutSessionModel()
    @State private var selection: Item? = .jobFeed
    // The server stopped accepting the token mid-session.
    @State private var isSigningIn = false

    enum Item: String, CaseIterable, Identifiable {
        case jobFeed = "Job Feed"
        case drafts = "Drafts"
        case approvals = "Approvals"
        case applied = "Applied"
        case library = "Cover Letters"
        case identity = "Identity"

        // Identify each case by the value itself, not its raw string. The
        // sidebar List tags rows by `id`, and that tag type must match the
        // `selection` binding (`Item?`) or clicks never register a selection.
        var id: Self { self }
        var systemImage: String {
            switch self {
            case .jobFeed: return "tray.and.arrow.down"
            case .drafts: return "doc.text.magnifyingglass"
            case .approvals: return "checkmark.seal"
            case .applied: return "paperplane"
            case .library: return "books.vertical"
            case .identity: return "person.text.rectangle"
            }
        }
    }

    var body: some View {
        Group {
            if session.isSignedIn {
                // Rebuilt for each account, so none of the last one's rows linger.
                sections.id(session.generation)
            } else {
                WorksCoutSignInView(session: session)
            }
        }
        .tint(Brand.accent)
        .onChange(of: session.generation) { selection = .jobFeed }
        .sheet(isPresented: $isSigningIn) {
            VStack(spacing: 0) {
                WorksCoutSignInView(session: session) { isSigningIn = false }
                Button("Cancel") { isSigningIn = false }
                    .keyboardShortcut(.cancelAction)
                    .padding(.bottom)
            }
            .frame(minWidth: 420, minHeight: 440)
            .tint(Brand.accent)
        }
    }

    private var sections: some View {
        NavigationSplitView {
            List(Item.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.systemImage)
            }
            .navigationTitle("WORKS(c)OUT")
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    BrandMark(size: 28)
                    BrandWordmark(height: 18)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("WORKS(c)OUT")
                .accessibilityAddTraits(.isHeader)
            }
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        let client = session.client
        switch selection {
        case .jobFeed:
            JobFeedView(client: client, onUnauthorized: { isSigningIn = true })
                .navigationTitle("Job Feed")
        case .drafts:
            DraftsView(client: client, onUnauthorized: { isSigningIn = true })
                .navigationTitle("Drafts")
        case .approvals:
            ApprovalsView(client: client, onUnauthorized: { isSigningIn = true })
                .navigationTitle("Approvals")
        case .applied:
            AppliedView(client: client, onUnauthorized: { isSigningIn = true })
                .navigationTitle("Applied")
        case .library:
            CoverLetterLibraryView(client: client, onUnauthorized: { isSigningIn = true })
                .navigationTitle("Cover Letters")
        case .identity:
            IdentityView(client: client, onUnauthorized: { isSigningIn = true },
                         onSignOut: { session.signOut() })
                .navigationTitle("Identity")
        case nil:
            ContentUnavailableView("Pick a section", systemImage: "sidebar.left")
        }
    }
}
