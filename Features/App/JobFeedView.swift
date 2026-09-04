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

    var body: some View {
        Group {
            if isLoading && postings.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if postings.isEmpty {
                ContentUnavailableView(
                    "No postings yet",
                    systemImage: "tray",
                    description: Text("Scraped postings will show up here, best match first.")
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
        .refreshable { await load() }
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            postings = try await client.fetchIngestedPostings(status: .new)
            errorMessage = nil
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch {
            errorMessage = "Couldn't load the job feed: \(error)"
        }
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
        case 80...: return .green
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

            if let chips = posting.details?.summaryChips, !chips.isEmpty {
                Text(chips.joined(separator: " · "))
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
                detailSection("Your skills this job asks for", items: skills.matched, tint: .green)
            }
            if let skills = posting.skills, !skills.missing.isEmpty {
                detailSection("Asks for, not on your profile", items: skills.missing, tint: .indigo)
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

    /// Teal, and nothing else on the card uses it — recency is the thing she
    /// scans for first, and it shouldn't have to compete with the score or the
    /// account badge. Paired with a clock, since colour is never the only
    /// signal (CLAUDE.md §3.2).
    private func postedStamp(_ posted: String) -> some View {
        Label(posted.localizedCapitalized, systemImage: "clock.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.teal)
            .accessibilityLabel("Posted \(posted)")
    }

    /// Two counts, two colours, deliberately different shapes of information:
    /// green for what she brings, indigo for what she'd be learning. Indigo
    /// rather than red or orange because a gap is context, not a warning — and
    /// because orange already means "needs an account" on this card.
    private func skillPills(_ skills: PostingSkills) -> some View {
        HStack(spacing: 8) {
            if !skills.matched.isEmpty {
                pill(count: skills.matched.count,
                     noun: "skill match" + (skills.matched.count == 1 ? "" : "es"),
                     symbol: "checkmark.seal.fill",
                     tint: .green,
                     spoken: "\(skills.matched.count) of your skills match: \(skills.matched.joined(separator: ", "))")
            }
            if !skills.missing.isEmpty {
                pill(count: skills.missing.count,
                     noun: "to learn",
                     symbol: "book.fill",
                     tint: .indigo,
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
