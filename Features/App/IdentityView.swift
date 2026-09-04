import WorksCoutCore
import SwiftUI
import UniformTypeIdentifiers

struct IdentityView: View {
    let client: WorksCoutAPIClient
    let onUnauthorized: () -> Void

    @State private var skills: [Skill] = []
    @State private var links: [ProfileLink] = []
    @State private var resumes: [ResumeVersion] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pickingFile = false
    @State private var pickedFile: PickedFile?
    @State private var parsingResumeID: Int?
    @State private var addingSkillKey: String?
    @State private var removed: RemovedItem?
    @State private var isUndoing = false

    private static let allowedTypes: [UTType] = [
        .pdf,
        UTType(filenameExtension: "docx") ?? .data,
    ]

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
                    Section {
                        if resumes.isEmpty {
                            Text("No résumés uploaded yet. Add one to get AI-suggested skills.")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                        ForEach(resumes) { resume in
                            ResumeRow(
                                resume: resume,
                                isParsing: parsingResumeID == resume.id,
                                addingSkillKey: addingSkillKey,
                                onParse: { Task { await parse(resume) } },
                                onRemove: { Task { await remove(resume) } },
                                onAddSkill: { suggestion in Task { await addSkill(suggestion, from: resume) } }
                            )
                        }
                    } header: {
                        Text("Résumés")
                    }
                }
                .listStyle(.inset)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let removed {
                UndoBanner(
                    removed: removed,
                    isWorking: isUndoing,
                    onUndo: { Task { await undoRemove(removed) } },
                    onDismiss: { self.removed = nil }
                )
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    pickingFile = true
                } label: {
                    Label("Add résumé", systemImage: "doc.badge.plus")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Upload a résumé")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: Self.allowedTypes) { result in
            if case .success(let url) = result {
                pickedFile = PickedFile(url: url)
            }
        }
        .sheet(item: $pickedFile) { file in
            ResumeUploadView(client: client, fileURL: file.url) {
                Task { await load() }
            }
        }
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

    private func parse(_ resume: ResumeVersion) async {
        parsingResumeID = resume.id
        defer { parsingResumeID = nil }
        do {
            let parsed = try await client.parseResume(id: resume.id)
            if let index = resumes.firstIndex(where: { $0.id == resume.id }) {
                resumes[index].parsedData = parsed
            }
            errorMessage = nil
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch WorksCoutAPIError.unavailable(let detail) {
            errorMessage = detail
        } catch WorksCoutAPIError.badRequest(let detail) {
            errorMessage = detail
        } catch {
            errorMessage = "Couldn't read suggestions from \(resume.title): \(error)"
        }
    }

    /// Remove without deleting: undo has to be able to put it back, and the
    /// parsed suggestions cost a model call to produce. No confirmation dialog
    /// — an Undo banner appears instead, per §3.5.
    private func remove(_ resume: ResumeVersion) async {
        do {
            _ = try await client.discardResume(id: resume.id)
            resumes.removeAll { $0.id == resume.id }
            removed = RemovedItem(id: resume.id, label: resume.title)
            errorMessage = nil
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch {
            errorMessage = "Couldn't remove \(resume.title): \(error)"
        }
    }

    private func undoRemove(_ item: RemovedItem) async {
        isUndoing = true
        defer { isUndoing = false }
        do {
            _ = try await client.restoreResume(id: item.id)
            removed = nil
            await load()
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch {
            errorMessage = "Couldn't put \(item.label) back: \(error)"
        }
    }

    /// Applying a suggestion is a normal skill creation, same as typing it in
    /// by hand — nothing about parsing writes anything on its own.
    private func addSkill(_ suggestion: ParsedSkillSuggestion, from resume: ResumeVersion) async {
        let key = "\(resume.id)-\(suggestion.name)"
        addingSkillKey = key
        defer { addingSkillKey = nil }
        do {
            let created = try await client.createSkill(
                NewSkill(name: suggestion.name, category: suggestion.category, proficiency: suggestion.proficiency)
            )
            skills.append(created)
            skills.sort { ($0.category, $0.name) < ($1.category, $1.name) }
            if let index = resumes.firstIndex(where: { $0.id == resume.id }) {
                resumes[index].parsedData.skills.removeAll { $0.name == suggestion.name }
            }
            errorMessage = nil
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch WorksCoutAPIError.badRequest {
            // Most likely "you already have a skill named this" — treat it as
            // already applied rather than showing an error for a non-problem.
            if let index = resumes.firstIndex(where: { $0.id == resume.id }) {
                resumes[index].parsedData.skills.removeAll { $0.name == suggestion.name }
            }
        } catch {
            errorMessage = "Couldn't add \(suggestion.name): \(error)"
        }
    }
}

private struct PickedFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ResumeRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let resume: ResumeVersion
    let isParsing: Bool
    let addingSkillKey: String?
    let onParse: () -> Void
    let onRemove: () -> Void
    let onAddSkill: (ParsedSkillSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(resume.title).font(.headline)
                    parseButton
                    removeButton
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(resume.title).font(.headline)
                    Spacer()
                    parseButton
                    removeButton
                }
            }

            if resume.parsedData.hasContent {
                suggestions
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    /// No confirmation dialog — an Undo banner appears instead, per §3.5.
    private var removeButton: some View {
        Button(role: .destructive, action: onRemove) {
            Label("Remove", systemImage: "xmark.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Remove \(resume.title) from your résumés")
    }

    private var parseButton: some View {
        Button(action: onParse) {
            if isParsing {
                ProgressView()
            } else if resume.parsedData.hasContent {
                Label("Re-check", systemImage: "arrow.clockwise")
            } else {
                Label("Suggest skills", systemImage: "sparkles")
            }
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        .disabled(isParsing)
        .accessibilityLabel(
            resume.parsedData.hasContent
                ? "Re-check \(resume.title) for skill suggestions"
                : "Suggest skills from \(resume.title)"
        )
    }

    @ViewBuilder
    private var suggestions: some View {
        if resume.parsedData.unparsed {
            Label("Couldn't extract structured suggestions from this file.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if resume.parsedData.skills.isEmpty {
            Label("No new skills found beyond what's already listed above.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggested skills").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(resume.parsedData.skills) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: ParsedSkillSuggestion) -> some View {
        let key = "\(resume.id)-\(suggestion.name)"
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text(suggestion.name)
                    addButton(for: suggestion, key: key)
                }
            } else {
                HStack {
                    Text(suggestion.name)
                    Spacer()
                    addButton(for: suggestion, key: key)
                }
            }
        }
    }

    private func addButton(for suggestion: ParsedSkillSuggestion, key: String) -> some View {
        Button {
            onAddSkill(suggestion)
        } label: {
            if addingSkillKey == key {
                ProgressView()
            } else {
                Label("Add", systemImage: "plus.circle")
            }
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(addingSkillKey == key)
        .accessibilityLabel("Add \(suggestion.name) to your skills")
    }
}
