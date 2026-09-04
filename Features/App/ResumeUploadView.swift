import WorksCoutCore
import SwiftUI

/// Uploads a picked PDF/DOCX as a new résumé version.
///
/// The server enforces the real limits — size cap, PDF/DOCX only checked
/// against the file's actual bytes not just its extension, and a cap on how
/// many résumé versions one account can keep. This only sets a sensible
/// starting title and shows whatever the server says if it refuses the file.
struct ResumeUploadView: View {
    let client: WorksCoutAPIClient
    let fileURL: URL
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(client: WorksCoutAPIClient, fileURL: URL, onSaved: @escaping () -> Void) {
        self.client = client
        self.fileURL = fileURL
        self.onSaved = onSaved
        _title = State(initialValue: fileURL.deletingPathExtension().lastPathComponent)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)

                Label(fileURL.lastPathComponent, systemImage: "doc")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Add Résumé")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Uploading…" : "Upload") { Task { await save() } }
                        .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        guard fileURL.startAccessingSecurityScopedResource() else {
            errorMessage = "Couldn't access that file."
            return
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: fileURL)
            let isDocx = fileURL.pathExtension.lowercased() == "docx"
            let mimeType = isDocx
                ? "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
                : "application/pdf"
            _ = try await client.uploadResume(
                title: title, fileData: data, filename: fileURL.lastPathComponent, mimeType: mimeType
            )
            onSaved()
            dismiss()
        } catch let error as WorksCoutAPIError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Couldn't read that file."
        }
    }

    private static func message(for error: WorksCoutAPIError) -> String {
        switch error {
        case .badRequest(let detail), .unavailable(let detail):
            return detail
        default:
            return "Couldn't upload this résumé."
        }
    }
}
