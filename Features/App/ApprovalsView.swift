import WorksCoutCore
import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Stage three: approved and waiting to go out.
///
/// One button, and it's the one that matters — it copies the cover letter,
/// opens the employer's form, and moves the application to Applied. It does not
/// submit: these portals ask, under her name, about work authorisation and EEO
/// identification, and those answers are hers to give.
struct ApprovalsView: View {
    let client: WorksCoutAPIClient
    let onUnauthorized: () -> Void

    @State private var applications: [Application] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var workingID: Int?

    private var approved: [Application] { applications.filter(\.isApproved) }

    var body: some View {
        Group {
            if isLoading && applications.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if approved.isEmpty {
                ContentUnavailableView(
                    "Nothing approved yet",
                    systemImage: "checkmark.seal",
                    description: Text("Approve a draft and it moves here, ready to send.")
                )
            } else {
                List(approved) { application in
                    ApprovalRow(
                        application: application,
                        isWorking: workingID == application.id,
                        onOpen: { open(application) },
                        onSubmitted: { Task { await markApplied(application) } }
                    )
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
            errorMessage = "Couldn't load approvals: \(error)"
        }
    }

    /// Copy first: every one of these portals wants the letter pasted into a box
    /// that can't be pre-filled from here.
    private func open(_ application: Application) {
        if let letter = application.generatedMaterials?.coverLetter, !letter.isEmpty {
            #if os(iOS)
            UIPasteboard.general.string = letter
            #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(letter, forType: .string)
            #endif
        }
        guard let link = application.bestApplyLink else { return }
        #if os(iOS)
        UIApplication.shared.open(link)
        #else
        NSWorkspace.shared.open(link)
        #endif
    }

    private func markApplied(_ application: Application) async {
        workingID = application.id
        defer { workingID = nil }
        do {
            _ = try await client.markApplied(applicationID: application.id)
            applications.removeAll { $0.id == application.id }
        } catch {
            errorMessage = "Couldn't record \(application.roleTitle): \(error)"
        }
    }
}

private struct ApprovalRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let application: Application
    let isWorking: Bool
    let onOpen: () -> Void
    let onSubmitted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(application.roleTitle).font(.headline)
                Text(application.companyName).font(.subheadline).foregroundStyle(.secondary)
            }

            if application.driveResumeLink != nil || application.driveCoverLetterLink != nil {
                HStack(spacing: 12) {
                    if let resume = application.driveResumeLink {
                        Link(destination: resume) {
                            Label("Resume", systemImage: "doc.richtext").font(.caption)
                        }
                        .frame(minHeight: 44)
                    }
                    if let letter = application.driveCoverLetterLink {
                        Link(destination: letter) {
                            Label("Cover letter", systemImage: "doc.richtext").font(.caption)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }

            actions
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actions: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) { buttons }
        } else {
            HStack(spacing: 10) { buttons; Spacer() }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: onOpen) {
            Label("Copy letter and open", systemImage: "arrow.up.right.square")
        }
        .buttonStyle(.borderedProminent)
        .frame(minHeight: 44)
        .accessibilityLabel("Copy the cover letter and open the form for \(application.roleTitle)")

        Button(action: onSubmitted) {
            if isWorking {
                ProgressView()
            } else {
                Label("I submitted this", systemImage: "paperplane")
            }
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        .disabled(isWorking)
        .accessibilityLabel("Mark \(application.roleTitle) as submitted and move it to Applied")
    }
}
