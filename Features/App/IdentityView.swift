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
    // Which Job-Feed filters this account wants surfaced. Edited here so the
    // feed's filter bar stays legible; saved straight to the server on toggle.
    @State private var filterPreferences = JobFilterPreferences()
    // The user's own AI provider keys (masked). Adding one routes their
    // generation/parsing through their subscription instead of the server's.
    @State private var aiCredentials: [AICredential] = []
    @State private var newAIProvider: AIProvider = .anthropic
    @State private var newAIKey = ""
    @State private var newAIModel = ""
    @State private var newAIBaseURL = ""
    @State private var savingAI = false

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
                    filterSection
                    aiProviderSection
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
            // Best-effort: the filter section falls back to defaults if this
            // fails, and it must not block the rest of Identity from loading.
            if let prefs = try? await client.fetchFilterPreferences() {
                filterPreferences = prefs
            }
            if let creds = try? await client.fetchAICredentials() {
                aiCredentials = creds
            }
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

    // MARK: Job filters

    /// Checkboxes choosing which filters appear in the Job Feed, so its filter
    /// bar shows only what she wants rather than every possible facet at once.
    private var filterSection: some View {
        Section {
            Toggle("Salary range", isOn: filterBinding(\.salary))
            Toggle("Remote only", isOn: filterBinding(\.remote))
            Toggle("Job type", isOn: filterBinding(\.jobType))
            Toggle("Match score", isOn: filterBinding(\.matchScore))
        } header: {
            Text("Job filters")
        } footer: {
            Text("Choose which filters appear in the Job Feed. Fewer means a simpler filter bar.")
        }
    }

    /// Each toggle writes the whole preferences object back to the server. The
    /// change is optimistic locally; `saveFilterPreferences` reverts on failure.
    private func filterBinding(_ keyPath: WritableKeyPath<JobFilterPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { filterPreferences[keyPath: keyPath] },
            set: { newValue in
                let previous = filterPreferences
                filterPreferences[keyPath: keyPath] = newValue
                Task { await saveFilterPreferences(revertingTo: previous) }
            }
        )
    }

    private func saveFilterPreferences(revertingTo previous: JobFilterPreferences) async {
        do {
            filterPreferences = try await client.updateFilterPreferences(filterPreferences)
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch {
            filterPreferences = previous
            errorMessage = "Couldn't save filter settings: \(error)"
        }
    }

    // MARK: AI provider

    /// Bring-your-own-key: pick a provider, paste its API key, and generation +
    /// résumé parsing run on that instead of the server's default.
    private var aiProviderSection: some View {
        Section {
            ForEach(aiCredentials) { cred in
                aiCredentialRow(cred)
            }
            Picker("Provider", selection: $newAIProvider) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            SecureField("API key", text: $newAIKey)
            TextField(newAIProvider.modelPlaceholder, text: $newAIModel)
                .autocorrectionDisabled()
            if newAIProvider.needsBaseURL {
                TextField("Base URL (https://…)", text: $newAIBaseURL)
                    .autocorrectionDisabled()
            }
            Button {
                Task { await saveAICredential() }
            } label: {
                if savingAI {
                    ProgressView()
                } else {
                    Text("Save & use \(newAIProvider.displayName)")
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .disabled(saveAIDisabled)
            if let url = newAIProvider.keyURL {
                Link("Get an API key for \(newAIProvider.displayName)", destination: url)
                    .font(.footnote)
            }
        } header: {
            Text("AI provider")
        } footer: {
            Text("Bring your own AI by pasting an API key — not a subscription — from the provider's developer console. It's stored encrypted and used to write your materials. Leave it unset to use the built-in default.")
        }
    }

    private var saveAIDisabled: Bool {
        savingAI
            || newAIKey.trimmingCharacters(in: .whitespaces).isEmpty
            || (newAIProvider.needsBaseURL && newAIBaseURL.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @ViewBuilder
    private func aiCredentialRow(_ cred: AICredential) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cred.provider.displayName)
                Text("\(cred.model.isEmpty ? cred.provider.modelPlaceholder : cred.model) · key \(cred.maskedKey)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if cred.isActive {
                Label("In use", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(cred.provider.displayName) is in use")
            } else {
                Button("Use") { Task { await activateAICredential(cred) } }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Use \(cred.provider.displayName)")
            }
            Button(role: .destructive) {
                Task { await removeAICredential(cred) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Remove the \(cred.provider.displayName) key")
        }
    }

    private func loadAICredentials() async {
        if let creds = try? await client.fetchAICredentials() {
            aiCredentials = creds
        }
    }

    private func saveAICredential() async {
        savingAI = true
        defer { savingAI = false }
        do {
            _ = try await client.saveAICredential(
                NewAICredential(
                    provider: newAIProvider,
                    apiKey: newAIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: newAIModel.trimmingCharacters(in: .whitespacesAndNewlines),
                    baseUrl: newAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            newAIKey = ""; newAIModel = ""; newAIBaseURL = ""
            await loadAICredentials()
            errorMessage = nil
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch WorksCoutAPIError.badRequest(let detail) {
            errorMessage = detail
        } catch {
            errorMessage = "Couldn't save the AI key: \(error)"
        }
    }

    private func activateAICredential(_ cred: AICredential) async {
        do {
            _ = try await client.activateAICredential(id: cred.id)
            await loadAICredentials()
        } catch {
            errorMessage = "Couldn't switch to \(cred.provider.displayName): \(error)"
        }
    }

    private func removeAICredential(_ cred: AICredential) async {
        do {
            try await client.deleteAICredential(id: cred.id)
            await loadAICredentials()
        } catch {
            errorMessage = "Couldn't remove \(cred.provider.displayName): \(error)"
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
