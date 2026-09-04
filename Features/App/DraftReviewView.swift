import WorksCoutCore
import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Read the draft and fix the wording, then approve it.
///
/// Approving is the only outward action here: it moves the application to the
/// Approvals stage. Opening the employer's form and recording the submission
/// happen there, so each screen in the pipeline does exactly one thing.
struct DraftReviewView: View {
    let client: WorksCoutAPIClient
    let application: Application
    let onChange: (Application) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var current: Application
    @State private var letter: String
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var isWorking = false
    @State private var message: String?

    init(client: WorksCoutAPIClient, application: Application, onChange: @escaping (Application) -> Void) {
        self.client = client
        self.application = application
        self.onChange = onChange
        _current = State(initialValue: application)
        _letter = State(initialValue: application.generatedMaterials?.coverLetter ?? "")
    }

    private var materials: ApplicationMaterials? { current.generatedMaterials }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    coverLetterSection

                    if let materials {
                        if !materials.resumeSummary.isEmpty {
                            block("Resume summary", text: materials.resumeSummary)
                        }
                        if !materials.resumeBullets.isEmpty {
                            block("Resume bullets",
                                  text: materials.resumeBullets.map { "• \($0)" }.joined(separator: "\n"))
                        }
                        if !materials.gaps.isEmpty { gapsSection(materials.gaps) }
                    } else {
                        ContentUnavailableView("No draft yet", systemImage: "doc",
                                               description: Text("Nothing has been generated for this application."))
                    }

                    documentsSection
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle("Review draft")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(current.roleTitle).font(.title3.weight(.semibold))
            Text(current.companyName).foregroundStyle(.secondary)
            StatusChip(status: current.status)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var coverLetterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cover letter").font(.headline)
                Spacer()
                Button(isEditing ? "Cancel" : "Edit") {
                    if isEditing { letter = materials?.coverLetter ?? "" }
                    isEditing.toggle()
                }
                .font(.caption)
                .frame(minHeight: 44)
                Button {
                    copy(letter)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc").font(.caption)
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Copy cover letter")
            }

            if isEditing {
                TextEditor(text: $letter)
                    .font(.callout)
                    .frame(minHeight: 280)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                    .accessibilityLabel("Cover letter text")

                Button {
                    Task { await saveLetter() }
                } label: {
                    if isSaving { ProgressView() } else { Text("Save and re-render PDFs") }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .disabled(isSaving || letter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Text(letter)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func gapsSection(_ gaps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gaps they'll probe").font(.headline)
            Text("Only you see these — they're interview prep, not part of the application.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(gaps, id: \.self) { gap in
                Text(gap).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Documents in Drive").font(.headline)
            if let resume = current.driveResumeLink {
                Link(destination: resume) { Label("Resume PDF", systemImage: "doc.richtext") }
                    .frame(minHeight: 44)
            }
            if let letterLink = current.driveCoverLetterLink {
                Link(destination: letterLink) { Label("Cover letter PDF", systemImage: "doc.richtext") }
                    .frame(minHeight: 44)
            }
            if current.driveResumeLink == nil && current.driveCoverLetterLink == nil {
                Text("PDFs haven't been uploaded for this one yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func block(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button { copy(text) } label: {
                    Label("Copy", systemImage: "doc.on.doc").font(.caption)
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Copy \(title)")
            }
            Text(text).font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 8) {
            if current.status == .approved {
                Label("Approved — send it from the Approvals tab.", systemImage: "checkmark.seal.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await approve() }
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Label("Approve this draft", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .disabled(isWorking || materials == nil)
                .accessibilityLabel("Approve this draft and move it to Approvals")
            }
        }
        .padding()
        .background(.bar)
    }

    private func apply(_ updated: Application) {
        current = updated
        letter = updated.generatedMaterials?.coverLetter ?? letter
        onChange(updated)
    }

    private func saveLetter() async {
        guard var edited = materials else { return }
        isSaving = true
        defer { isSaving = false }
        edited.coverLetter = letter
        do {
            apply(try await client.editMaterials(applicationID: current.id, materials: edited))
            isEditing = false
            message = "Saved. The PDFs in Drive have been re-rendered with your wording."
        } catch {
            message = "Couldn't save your edit: \(error)"
        }
    }

    private func approve() async {
        isWorking = true
        defer { isWorking = false }
        do {
            apply(try await client.approveApplication(id: current.id))
            message = "Approved. It's in the Approvals tab when you're ready to send it."
        } catch {
            message = "Couldn't approve that: \(error)"
        }
    }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

}
