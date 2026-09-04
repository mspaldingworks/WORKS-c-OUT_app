import SwiftUI
import WorksCoutCore

/// Sidebar + detail on the Mac, same pipeline order as the phone.
struct WorksCoutMacRootView: View {
    @State private var client = WorksCoutConfig.makeClient()
    @State private var selection: Item? = .jobFeed
    @State private var isConnecting = false

    enum Item: String, CaseIterable, Identifiable {
        case jobFeed = "Job Feed"
        case drafts = "Drafts"
        case approvals = "Approvals"
        case applied = "Applied"
        case identity = "Identity"

        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .jobFeed: return "tray.and.arrow.down"
            case .drafts: return "doc.text.magnifyingglass"
            case .approvals: return "checkmark.seal"
            case .applied: return "paperplane"
            case .identity: return "person.text.rectangle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Item.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.systemImage)
            }
            .navigationTitle("WORKS(c)OUT")
            .listStyle(.sidebar)
        } detail: {
            detail
        }
        .toolbar {
            if WorksCoutConfig.resolvedToken == nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Connect") { isConnecting = true }
                }
            }
        }
        .sheet(isPresented: $isConnecting) {
            WorksCoutSetupView { token in
                WorksCoutKeychain.saveToken(token)
                client = WorksCoutConfig.makeClient()
                isConnecting = false
            }
            .frame(minWidth: 420, minHeight: 260)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .jobFeed:
            JobFeedView(client: client, onUnauthorized: { isConnecting = true })
                .navigationTitle("Job Feed")
        case .drafts:
            DraftsView(client: client, onUnauthorized: { isConnecting = true })
                .navigationTitle("Drafts")
        case .approvals:
            ApprovalsView(client: client, onUnauthorized: { isConnecting = true })
                .navigationTitle("Approvals")
        case .applied:
            AppliedView(client: client, onUnauthorized: { isConnecting = true })
                .navigationTitle("Applied")
        case .identity:
            IdentityView(client: client, onUnauthorized: { isConnecting = true })
                .navigationTitle("Identity")
        case nil:
            ContentUnavailableView("Pick a section", systemImage: "sidebar.left")
        }
    }
}
