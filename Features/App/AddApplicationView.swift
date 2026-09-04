import WorksCoutCore
import SwiftUI

/// Add a job found outside the feed. It enters the pipeline at Drafts, the
/// same place a scraped posting does.
struct AddApplicationView: View {
    let client: WorksCoutAPIClient
    let companies: [Company]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var companyName = ""
    @State private var roleTitle = ""
    @State private var jobURL = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Company", text: $companyName)
                TextField("Role title", text: $roleTitle)
                TextField("Job URL (optional)", text: $jobURL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Add Application")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(companyName.isEmpty || roleTitle.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let company: Company
            if let existing = companies.first(where: { $0.name.caseInsensitiveCompare(companyName) == .orderedSame }) {
                company = existing
            } else {
                company = try await client.createCompany(NewCompany(name: companyName))
            }
            _ = try await client.createApplication(NewApplication(company: company.id, roleTitle: roleTitle, jobUrl: jobURL))
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Couldn't save: \(error)"
        }
    }
}
