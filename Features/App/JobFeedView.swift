import WorksCoutCore
import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Postings pushed in by the Apify scrapers, ranked best-fit first by the
/// server. One button per job: Apply writes the materials, saves the
/// application, and opens the employer's form.
struct JobFeedView: View {
    let client: WorksCoutAPIClient
    let onUnauthorized: () -> Void

    @State private var postings: [IngestedPosting] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var applyingID: Int?
    @State private var expanded: Set<Int> = []
    @State private var removed: RemovedItem?
    @State private var isUndoing = false

    // Which filters the user has chosen to surface (Identity → Job filters), and
    // the active selections applied to the feed request. Only enabled facets
    // appear in the bar; the salary brackets are checkboxes that collapse to a
    // single min/max range sent to the server.
    @State private var preferences = JobFilterPreferences()
    @State private var filter = JobFilterQuery()
    @State private var selectedBrackets: Set<String> = []
    @State private var includeUnspecifiedSalary = true
    // What's typed in the search field; copied into `filter.search` after a
    // short pause so each keystroke isn't a request.
    @State private var searchText = ""
    // The saved sort is applied once per appearance, not on every reload.
    @State private var appliedSavedSort = false

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            content
        }
        .searchable(text: $searchText, prompt: "Search titles, companies, descriptions")
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
        .task { await load() }
        .task(id: searchText) {
            // Debounce: a new keystroke cancels this task before it lands.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, filter.search != searchText else { return }
            filter.search = searchText
        }
        .onChange(of: filter) { Task { await loadPostings() } }
        .onChange(of: filter.sort) { _, sort in
            if sort == .closest && !preferences.hasHome {
                filter.sort = .best
            } else {
                Task { await rememberSort(sort) }
            }
        }
        .onChange(of: selectedBrackets) { recomputeSalary() }
        .onChange(of: includeUnspecifiedSalary) { recomputeSalary() }
        .refreshable { await loadPostings() }
        .refreshButton("Refresh the job feed", isRefreshing: isLoading) { await loadPostings() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && postings.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if postings.isEmpty {
            ContentUnavailableView(
                filtersActive ? "No jobs match these filters" : "No postings yet",
                systemImage: filtersActive ? "line.3.horizontal.decrease.circle" : "tray",
                description: Text(filtersActive
                    ? "Try widening or clearing the filters or search above."
                    : "Scraped postings will show up here, best match first.")
            )
        } else {
            List(postings) { posting in
                PostingRow(
                    posting: posting,
                    isApplying: applyingID == posting.id,
                    isExpanded: expanded.contains(posting.id),
                    onToggleDetails: { toggleDetails(posting) },
                    onApply: { Task { await applyTo(posting) } },
                    onSignIn: { openSignIn(posting) },
                    onRemove: { Task { await remove(posting) } }
                )
            }
            .listStyle(.inset)
        }
    }

    private func remove(_ posting: IngestedPosting) async {
        do {
            _ = try await client.dismissPosting(id: posting.id)
            postings.removeAll { $0.id == posting.id }
            removed = RemovedItem(id: posting.id, label: posting.title)
        } catch {
            errorMessage = "Couldn't remove \(posting.title): \(error)"
        }
    }

    private func undoRemove(_ item: RemovedItem) async {
        isUndoing = true
        defer { isUndoing = false }
        do {
            _ = try await client.restorePosting(id: item.id)
            removed = nil
            await load()
        } catch {
            errorMessage = "Couldn't put \(item.label) back: \(error)"
        }
    }

    private func toggleDetails(_ posting: IngestedPosting) {
        if expanded.contains(posting.id) {
            expanded.remove(posting.id)
        } else {
            expanded.insert(posting.id)
        }
    }

    private var filtersActive: Bool { !filter.isEmpty }

    private func load() async {
        await loadPreferences()
        if !appliedSavedSort {
            appliedSavedSort = true
            // Closest needs a home; without one the server would quietly fall
            // back to best match while the menu still said "Closest".
            let saved = preferences.sort == .closest && !preferences.hasHome ? .best : preferences.sort
            if filter.sort != saved {
                filter.sort = saved  // onChange(of: filter) does the load
                return
            }
        }
        await loadPostings()
    }

    /// The sort is remembered across launches. Only the one field is sent, so
    /// this can't overwrite filter settings changed on the Identity screen.
    private func rememberSort(_ sort: JobSort) async {
        guard preferences.sort != sort else { return }
        preferences.sort = sort
        _ = try? await client.updateFilterSort(sort)
    }

    /// Which filters to surface is the user's choice (Identity → Job filters). A
    /// failure here just leaves the defaults; the feed still works without a bar.
    private func loadPreferences() async {
        if let prefs = try? await client.fetchFilterPreferences() {
            preferences = prefs
        }
    }

    private func loadPostings() async {
        isLoading = true
        defer { isLoading = false }
        do {
            postings = try await client.fetchIngestedPostings(status: .new, filter: filter)
            errorMessage = nil
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch {
            errorMessage = "Couldn't load the job feed: \(error)"
        }
    }

    /// Collapse the ticked salary brackets into one min/max range for the server.
    /// A nil floor/ceiling in the selection means open-ended on that side
    /// ("Under $30k" has no floor, "$100k+" no ceiling).
    private func recomputeSalary() {
        let chosen = Self.salaryBrackets.filter { selectedBrackets.contains($0.id) }
        if chosen.isEmpty {
            filter.salaryMin = nil
            filter.salaryMax = nil
        } else {
            let mins = chosen.map(\.min)
            let maxes = chosen.map(\.max)
            filter.salaryMin = mins.contains(nil) ? nil : mins.compactMap { $0 }.min()
            filter.salaryMax = maxes.contains(nil) ? nil : maxes.compactMap { $0 }.max()
        }
        filter.includeUnspecifiedSalary = includeUnspecifiedSalary
    }

    /// One tap does the whole thing: write the materials if they're missing,
    /// track the application, then open the employer's portal. Generating takes
    /// about 40 seconds the first time, which is why the row shows progress
    /// rather than appearing to hang.
    private func applyTo(_ posting: IngestedPosting) async {
        applyingID = posting.id
        defer { applyingID = nil }
        do {
            var job = try await client.prepareApplications(postingIDs: [posting.id])
            while !job.isFinished {
                try await Task.sleep(for: .seconds(3))
                job = try await client.prepareStatus(jobID: job.id)
            }
            if let failure = job.failures.first {
                errorMessage = failure.detail
            }
            if let link = posting.bestApplyLink {
                openURL(link)
            }
            postings.removeAll { $0.id == posting.id }
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch {
            errorMessage = "Couldn't prepare \(posting.title): \(error)"
        }
    }

    private func openSignIn(_ posting: IngestedPosting) {
        if let link = posting.signInLink { openURL(link) }
    }

    private func openURL(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: Filter bar

    fileprivate struct SalaryBracket: Identifiable {
        let id: String
        let label: String
        let min: Int?
        let max: Int?
    }

    fileprivate struct JobTypeOption: Identifiable {
        let token: String
        let label: String
        var id: String { token }
    }

    fileprivate struct ScoreOption: Identifiable {
        let value: Int?
        let label: String
        var id: String { label }
    }

    fileprivate struct DayOption: Identifiable {
        let days: Int?
        let label: String
        var id: String { label }
    }

    fileprivate static let salaryBrackets: [SalaryBracket] = [
        .init(id: "u30", label: "Under $30k", min: nil, max: 30_000),
        .init(id: "30-50", label: "$30k – $50k", min: 30_000, max: 50_000),
        .init(id: "50-75", label: "$50k – $75k", min: 50_000, max: 75_000),
        .init(id: "75-100", label: "$75k – $100k", min: 75_000, max: 100_000),
        .init(id: "100", label: "$100k+", min: 100_000, max: nil),
    ]

    private static let jobTypeOptions: [JobTypeOption] = [
        .init(token: "full_time", label: "Full-time"),
        .init(token: "part_time", label: "Part-time"),
        .init(token: "contract", label: "Contract"),
        .init(token: "temporary", label: "Temporary"),
        .init(token: "internship", label: "Internship"),
    ]

    private static let scoreOptions: [ScoreOption] = [
        .init(value: nil, label: "Any match"),
        .init(value: 55, label: "55+"),
        .init(value: 70, label: "70+"),
        .init(value: 80, label: "80+"),
    ]

    private static let radiusOptions = [5, 10, 25, 50, 100]

    private static let postedOptions: [DayOption] = [
        .init(days: nil, label: "Any time"),
        .init(days: 1, label: "Past 24 hours"),
        .init(days: 3, label: "Past 3 days"),
        .init(days: 7, label: "Past week"),
        .init(days: 14, label: "Past 2 weeks"),
        .init(days: 30, label: "Past month"),
    ]

    /// Sort leads and is always there; the filters after it are whichever ones
    /// she has switched on in Identity → Job filters.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                sortMenu
                if preferences.remote { workplaceMenu }
                if preferences.distance { distanceMenu }
                if preferences.postedDate { postedMenu }
                if preferences.salary { salaryMenu }
                if preferences.jobType { jobTypeMenu }
                if preferences.matchScore { scoreMenu }
                if preferences.easyApply { noAccountChip }
                if filtersActive { clearButton }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $filter.sort) {
                ForEach(JobSort.allCases) { sort in
                    Label(sort.label, systemImage: sort.systemImage)
                        .tag(sort)
                        .selectionDisabled(sort == .closest && !preferences.hasHome)
                }
            }
            .pickerStyle(.inline)
            if !preferences.hasHome {
                Text("Set a home location in Identity → Job filters to sort by distance.")
            }
        } label: {
            chipLabel(filter.sort.label, systemImage: "arrow.up.arrow.down",
                      active: filter.sort != .best)
        }
        .accessibilityLabel("Sort by \(filter.sort.label)")
        .accessibilityHint("Changes the order of the job feed")
    }

    private var workplaceMenu: some View {
        Menu {
            ForEach(Workplace.allCases) { workplace in
                Toggle(isOn: workplaceBinding(workplace)) {
                    Label(workplace.label, systemImage: workplace.systemImage)
                }
            }
        } label: {
            chipLabel(workplaceTitle, systemImage: "house", active: !filter.workplaces.isEmpty)
        }
        .accessibilityLabel("Filter by workplace: \(workplaceTitle)")
    }

    private var workplaceTitle: String {
        switch filter.workplaces.count {
        case 0: return "Workplace"
        case 1: return filter.workplaces[0].label
        default: return filter.workplaces.map(\.label).joined(separator: " + ")
        }
    }

    private func workplaceBinding(_ workplace: Workplace) -> Binding<Bool> {
        Binding(
            get: { filter.workplaces.contains(workplace) },
            set: { isOn in
                if isOn {
                    if !filter.workplaces.contains(workplace) { filter.workplaces.append(workplace) }
                    // Keep the order stable whatever order they were ticked in.
                    filter.workplaces.sort { lhs, rhs in
                        Workplace.allCases.firstIndex(of: lhs)! < Workplace.allCases.firstIndex(of: rhs)!
                    }
                } else {
                    filter.workplaces.removeAll { $0 == workplace }
                }
            }
        )
    }

    /// Straight-line miles from the home saved in Identity. Without a home there
    /// is nothing to measure from, so the menu says where to set one instead.
    private var distanceMenu: some View {
        Menu {
            if preferences.hasHome {
                Section("From \(preferences.homeLabel.isEmpty ? "home" : preferences.homeLabel)") {
                    Button {
                        filter.withinMiles = nil
                    } label: {
                        checkedLabel("Any distance", checked: filter.withinMiles == nil)
                    }
                    ForEach(Self.radiusOptions, id: \.self) { miles in
                        Button {
                            filter.withinMiles = miles
                        } label: {
                            checkedLabel(miles == preferences.radiusMiles
                                            ? "Within \(miles) mi (your default)"
                                            : "Within \(miles) mi",
                                         checked: filter.withinMiles == miles)
                        }
                    }
                    if !Self.radiusOptions.contains(preferences.radiusMiles) {
                        Button {
                            filter.withinMiles = preferences.radiusMiles
                        } label: {
                            checkedLabel("Within \(preferences.radiusMiles) mi (your default)",
                                         checked: filter.withinMiles == preferences.radiusMiles)
                        }
                    }
                }
                Divider()
                Toggle("Include remote jobs", isOn: $filter.includeRemoteInRadius)
            } else {
                Text("Set a home location in Identity → Job filters to filter by distance.")
            }
        } label: {
            chipLabel(filter.withinMiles.map { "Within \($0) mi" } ?? "Distance",
                      systemImage: "location", active: filter.withinMiles != nil)
        }
        .accessibilityLabel(filter.withinMiles.map { "Showing jobs within \($0) miles of home" }
                            ?? "Filter by distance from home")
    }

    private var postedMenu: some View {
        Menu {
            ForEach(Self.postedOptions) { option in
                Button {
                    filter.postedWithinDays = option.days
                } label: {
                    checkedLabel(option.label, checked: filter.postedWithinDays == option.days)
                }
            }
        } label: {
            chipLabel(postedTitle, systemImage: "calendar", active: filter.postedWithinDays != nil)
        }
        .accessibilityLabel("Filter by posting date: \(postedTitle)")
    }

    private var postedTitle: String {
        guard let days = filter.postedWithinDays else { return "Posted" }
        return Self.postedOptions.first { $0.days == days }?.label ?? "Past \(days) days"
    }

    private var salaryMenu: some View {
        Menu {
            ForEach(Self.salaryBrackets) { bracket in
                Toggle(bracket.label, isOn: bracketBinding(bracket.id))
            }
            Divider()
            Toggle("Include jobs with no listed pay", isOn: $includeUnspecifiedSalary)
        } label: {
            chipLabel(selectedBrackets.isEmpty ? "Salary" : "Salary (\(selectedBrackets.count))",
                      systemImage: "dollarsign.circle", active: !selectedBrackets.isEmpty)
        }
        .accessibilityLabel("Filter by salary range")
    }

    private func bracketBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selectedBrackets.contains(id) },
            set: { isOn in
                if isOn { selectedBrackets.insert(id) } else { selectedBrackets.remove(id) }
            }
        )
    }

    private var jobTypeMenu: some View {
        Menu {
            ForEach(Self.jobTypeOptions) { option in
                Toggle(option.label, isOn: jobTypeBinding(option.token))
            }
        } label: {
            chipLabel(filter.jobTypes.isEmpty ? "Job type" : "Job type (\(filter.jobTypes.count))",
                      systemImage: "briefcase", active: !filter.jobTypes.isEmpty)
        }
        .accessibilityLabel("Filter by job type")
    }

    private func jobTypeBinding(_ token: String) -> Binding<Bool> {
        Binding(
            get: { filter.jobTypes.contains(token) },
            set: { isOn in
                if isOn {
                    if !filter.jobTypes.contains(token) { filter.jobTypes.append(token) }
                } else {
                    filter.jobTypes.removeAll { $0 == token }
                }
            }
        )
    }

    private var scoreMenu: some View {
        Menu {
            ForEach(Self.scoreOptions) { option in
                Button {
                    filter.minScore = option.value
                } label: {
                    checkedLabel(option.label, checked: filter.minScore == option.value)
                }
            }
        } label: {
            chipLabel(filter.minScore.map { "Match \($0)+" } ?? "Match",
                      systemImage: "rosette", active: filter.minScore != nil)
        }
        .accessibilityLabel("Filter by minimum match score")
    }

    /// Hides Workday, iCIMS and the other portals that won't show the form
    /// without an account — the applications she can't finish from her phone.
    private var noAccountChip: some View {
        Button {
            filter.noAccountOnly.toggle()
        } label: {
            chipLabel("No account needed", systemImage: "person.crop.circle.badge.checkmark",
                      active: filter.noAccountOnly)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.noAccountOnly
            ? "Hiding jobs that need an account. Activate to show them."
            : "Hide jobs that need an account before applying")
    }

    private var clearButton: some View {
        Button {
            selectedBrackets.removeAll()
            includeUnspecifiedSalary = true
            searchText = ""
            filter = filter.cleared
        } label: {
            chipLabel("Clear", systemImage: "xmark.circle", active: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear all filters and search")
    }

    @ViewBuilder
    private func checkedLabel(_ title: String, checked: Bool) -> some View {
        if checked {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func chipLabel(_ title: String, systemImage: String, active: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(active ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                        in: Capsule())
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .frame(minHeight: 44)
    }
}

private struct PostingRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    let posting: IngestedPosting
    let isApplying: Bool
    let isExpanded: Bool
    let onToggleDetails: () -> Void
    let onApply: () -> Void
    let onSignIn: () -> Void
    let onRemove: () -> Void

    /// Green / amber / grey rather than a number alone, so the strength of a
    /// match reads at a glance without parsing digits.
    private var scoreColor: Color {
        switch posting.score {
        case 80...: return Brand.positive
        case 55..<80: return .orange
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(posting.score)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(scoreColor)
                    .accessibilityLabel("Match score \(posting.score) out of 100")

                VStack(alignment: .leading, spacing: 2) {
                    Text(posting.title).font(.headline)
                    HStack(spacing: 6) {
                        if !posting.companyName.isEmpty {
                            Text(posting.companyName).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if posting.requiresAccount {
                            accountBadge
                        }
                    }
                }
            }

            if let posted = posting.details?.posted, !posted.isEmpty {
                postedStamp(posted)
            }

            if !posting.cardChips.isEmpty {
                Text(posting.cardChips.joined(separator: " · "))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let skills = posting.skills, skills.hasAnything {
                skillPills(skills)
            }

            if !posting.scoreReasons.isEmpty {
                Text(posting.scoreReasons.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isExpanded, let details = posting.details {
                expandedDetails(details)
            }

            actions
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    /// Tapping the badge goes straight to the portal's sign-in page, because
    /// these platforms won't show the application form to a stranger — landing
    /// on the job post from a phone is a dead end otherwise.
    private var accountBadge: some View {
        Button(action: onSignIn) {
            Label(posting.platform.isEmpty ? "Account needed" : "\(posting.platform) account",
                  systemImage: "person.badge.key.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("\(posting.platform.isEmpty ? "This employer" : posting.platform) needs an account first. Opens the sign-in page.")
    }

    // Side by side these clip at accessibility text sizes, which CLAUDE.md §3.2
    // treats as a bug rather than a tradeoff.
    @ViewBuilder
    private var actions: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                applyButton
                detailsButton
                removeButton
            }
        } else {
            HStack(spacing: 10) {
                applyButton
                detailsButton
                Spacer()
                removeButton
            }
        }
    }

    private var detailsButton: some View {
        Button(action: onToggleDetails) {
            Label(isExpanded ? "Less" : "Details",
                  systemImage: isExpanded ? "chevron.up" : "chevron.down")
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
        .disabled(!(posting.details?.hasAnything ?? false))
        .accessibilityLabel(isExpanded
            ? "Hide the details for \(posting.title)"
            : "Show the full description and details for \(posting.title)")
    }

    /// The whole posting, in the app. Reading it here rather than on the
    /// employer's site is the entire point, so the description isn't truncated.
    @ViewBuilder
    private func expandedDetails(_ details: PostingDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // The posted date is on the collapsed card already; repeating it
            // here just pushes the description further down.
            if !details.companyRating.isEmpty {
                Label(details.companyRating, systemImage: "star")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Employer rated \(details.companyRating)")
            }

            if let skills = posting.skills, !skills.matched.isEmpty {
                detailSection("Your skills this job asks for", items: skills.matched, tint: Brand.positive)
            }
            if let skills = posting.skills, !skills.missing.isEmpty {
                detailSection("Asks for, not on your profile", items: skills.missing, tint: Brand.learn)
            }
            if !details.benefits.isEmpty {
                detailSection("Benefits", items: details.benefits)
            }
            if !details.requirements.isEmpty {
                detailSection("Requirements", items: details.requirements)
            }
            if !details.shifts.isEmpty {
                detailSection("Shifts", items: details.shifts)
            }

            if !details.description.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Full description").font(.subheadline.weight(.semibold))
                    Text(details.description)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func detailSection(_ title: String, items: [String], tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint ?? .primary)
            ForEach(items, id: \.self) { item in
                Text("• \(item)").font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Brand teal, and nothing else on the card uses it — recency is the thing she
    /// scans for first, and it shouldn't have to compete with the score or the
    /// account badge. Paired with a clock, since colour is never the only
    /// signal (CLAUDE.md §3.2).
    private func postedStamp(_ posted: String) -> some View {
        Label(posted.localizedCapitalized, systemImage: "clock.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Brand.fresh)
            .accessibilityLabel("Posted \(posted)")
    }

    /// Two counts, two colours, deliberately different shapes of information:
    /// green for what she brings, violet for what she'd be learning. Violet
    /// rather than red or orange because a gap is context, not a warning — and
    /// because orange already means "needs an account" on this card.
    private func skillPills(_ skills: PostingSkills) -> some View {
        HStack(spacing: 8) {
            if !skills.matched.isEmpty {
                pill(count: skills.matched.count,
                     noun: "skill match" + (skills.matched.count == 1 ? "" : "es"),
                     symbol: "checkmark.seal.fill",
                     tint: Brand.positive,
                     spoken: "\(skills.matched.count) of your skills match: \(skills.matched.joined(separator: ", "))")
            }
            if !skills.missing.isEmpty {
                pill(count: skills.missing.count,
                     noun: "to learn",
                     symbol: "book.fill",
                     tint: Brand.learn,
                     spoken: "\(skills.missing.count) skills you don't list: \(skills.missing.joined(separator: ", "))")
            }
            Spacer(minLength: 0)
        }
    }

    private func pill(count: Int, noun: String, symbol: String, tint: Color, spoken: String) -> some View {
        Label("\(count) \(noun)", systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityLabel(spoken)
    }

    /// No confirmation dialog — the feed shows an Undo banner instead, per
    /// CLAUDE.md §3.5.
    private var removeButton: some View {
        Button(role: .destructive, action: onRemove) {
            Label("Remove", systemImage: "xmark.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Remove \(posting.title) from the feed")
    }

    private var applyButton: some View {
        Button(action: onApply) {
            if isApplying {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Writing your materials…")
                }
            } else {
                Label("Apply", systemImage: "arrow.up.right.square")
            }
        }
        .buttonStyle(.borderedProminent)
        .frame(minHeight: 44)
        .disabled(isApplying)
        .accessibilityLabel(isApplying
            ? "Preparing your application for \(posting.title)"
            : "Apply to \(posting.title). Writes your cover letter and resume, saves it to the tracker, then opens the employer's form.")
    }
}
