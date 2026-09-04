import WorksCoutCore
import SwiftUI

struct IdentityView: View {
    let client: WorksCoutAPIClient
    let onUnauthorized: () -> Void

    @State private var skills: [Skill] = []
    @State private var links: [ProfileLink] = []
    @State private var resumes: [ResumeVersion] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && skills.isEmpty && links.isEmpty && resumes.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !links.isEmpty {
                        Section("Profile links") {
                            ForEach(links) { link in
                                if let url = URL(string: link.url) {
                                    Link(destination: url) {
                                        HStack {
                                            Text(link.platform)
                                            Spacer()
                                            Text(link.status.rawValue.replacingOccurrences(of: "_", with: " "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if !skills.isEmpty {
                        Section("Skills") {
                            ForEach(skills) { skill in
                                HStack {
                                    Text(skill.name)
                                    Spacer()
                                    Text(skill.proficiency.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !resumes.isEmpty {
                        Section("Resume versions") {
                            ForEach(resumes) { resume in
                                Text(resume.title)
                            }
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
            async let skillsTask = client.fetchSkills()
            async let linksTask = client.fetchLinks()
            async let resumesTask = client.fetchResumes()
            skills = try await skillsTask
            links = try await linksTask
            resumes = try await resumesTask
            errorMessage = nil
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch {
            errorMessage = "Couldn't load identity data: \(error)"
        }
    }
}
