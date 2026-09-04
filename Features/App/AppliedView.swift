import WorksCoutCore
import SwiftUI

/// Everything she's actually submitted, and where each one stands.
///
/// Separate from Drafts, which is work waiting on her, and from Applications,
/// which is the whole board including things never sent. This tab answers one
/// question: what did I apply to, and what happened?
struct AppliedView: View {
    let client: WorksCoutAPIClient
    let onUnauthorized: () -> Void

    @State private var applications: [Application] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var updatingID: Int?

    private var submitted: [Application] {
        applications.filter(\.isSubmitted)
    }

    /// Live applications first — a rejection three weeks ago matters less than
    /// an interview on Thursday.
    private var grouped: [(Application.Status, [Application])] {
        let order: [Application.Status] = [.offer, .interview, .phoneScreen, .applied,
                                           .rejected, .withdrawn]
        return order.compactMap { status in
            let items = submitted.filter { $0.status == status }
            return items.isEmpty ? nil : (status, items)
        }
    }

    var body: some View {
        Group {
            if isLoading && applications.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if submitted.isEmpty {
                ContentUnavailableView(
                    "Nothing submitted yet",
                    systemImage: "paperplane",
                    description: Text("Applications move here once you mark them submitted in Drafts.")
                )
            } else {
                List {
                    ForEach(grouped, id: \.0) { status, items in
                        Section {
                            ForEach(items) { application in
                                AppliedRow(
                                    application: application,
                                    isUpdating: updatingID == application.id,
                                    onAdvance: { next in
                                        Task { await advance(application, to: next) }
                                    }
                                )
                            }
                        } header: {
                            Text("\(status.label) (\(items.count))")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .padding(8)
                    .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            applications = try await client.fetchApplications()
            errorMessage = nil
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch {
            errorMessage = "Couldn't load your applications: \(error)"
        }
    }

    private func advance(_ application: Application, to status: Application.Status) async {
        updatingID = application.id
        defer { updatingID = nil }
        do {
            let updated = try await client.updateStatus(applicationID: application.id, status: status)
            if let index = applications.firstIndex(where: { $0.id == updated.id }) {
                applications[index] = updated
            }
        } catch {
            errorMessage = "Couldn't update \(application.roleTitle): \(error)"
        }
    }
}

private struct AppliedRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let application: Application
    let isUpdating: Bool
    let onAdvance: (Application.Status) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(application.roleTitle).font(.headline)
                Text(application.companyName).font(.subheadline).foregroundStyle(.secondary)
                if let applied = application.appliedDate {
                    Text("Applied \(applied)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if !application.nextSteps.isEmpty {
                stepControls
            }

            if let link = application.bestApplyLink {
                Link(destination: link) {
                    Label("View posting", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    // A row of four buttons clips at accessibility sizes, which CLAUDE.md §3.2
    // treats as a bug rather than a tradeoff.
    @ViewBuilder
    private var stepControls: some View {
        if isUpdating {
            ProgressView().frame(minHeight: 44)
        } else if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) { stepButtons }
        } else {
            HStack(spacing: 8) { stepButtons }
        }
    }

    @ViewBuilder
    private var stepButtons: some View {
        ForEach(application.nextSteps, id: \.self) { step in
            Button(step.label) { onAdvance(step) }
                .buttonStyle(.bordered)
                .font(.caption)
                .frame(minHeight: 44)
                .accessibilityLabel("Move \(application.roleTitle) to \(step.label)")
        }
    }
}
