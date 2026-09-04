import WorksCoutCore
import SwiftUI

/// Root of the Job Search tab. Opens straight to the Job Feed — there is no
/// setup gate. The token is baked in at build time (see WorksCoutConfig), and
/// if it's ever missing or rejected the feed says so inline and offers to
/// reconnect, rather than putting a screen in front of the jobs.
public struct WorksCoutRootTabView: View {
    @State private var client = WorksCoutConfig.makeClient()
    @State private var selectedSection = Section.jobFeed
    @State private var isConnecting = false

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
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedSection) {
                    ForEach(Section.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedSection {
                case .jobFeed:
                    JobFeedView(client: client, onUnauthorized: { isConnecting = true })
                case .drafts:
                    DraftsView(client: client, onUnauthorized: { isConnecting = true })
                case .approvals:
                    ApprovalsView(client: client, onUnauthorized: { isConnecting = true })
                case .applied:
                    AppliedView(client: client, onUnauthorized: { isConnecting = true })
                case .identity:
                    IdentityView(client: client, onUnauthorized: { isConnecting = true })
                }
            }
            .navigationTitle("Job Search")
            .toolbar {
                // Only surfaced when there's actually nothing to authenticate
                // with; otherwise it's clutter on a screen meant for reading jobs.
                if WorksCoutConfig.resolvedToken == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Connect") { isConnecting = true }
                    }
                }
            }
        }
        .sheet(isPresented: $isConnecting) {
            NavigationStack {
                WorksCoutSetupView { token in
                    WorksCoutKeychain.saveToken(token)
                    client = WorksCoutConfig.makeClient()
                    isConnecting = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isConnecting = false }
                    }
                }
            }
        }
    }
}
