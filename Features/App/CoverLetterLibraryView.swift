import QuickLook
import SwiftUI
import WorksCoutCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Every cover letter on the account in one place: the ones WORKS(c)OUT wrote
/// for a job and the ones she uploaded, sortable, filterable and searchable,
/// as a list or a grid. Each opens to the full letter, its PDF, or its Drive
/// copy — wherever the account keeps documents.
struct CoverLetterLibraryView: View {
    let client: WorksCoutAPIClient
    let onUnauthorized: () -> Void

    enum Layout: String { case list, grid }

    // Per device, not per account: how a screen is laid out is a property of
    // the screen it's on.
    @AppStorage("coverLetterLibraryLayout") private var layoutRaw = Layout.list.rawValue
    @AppStorage("coverLetterLibrarySort") private var sortRaw = CoverLetterSort.newest.rawValue
    @State private var source = CoverLetterSource.all
    @State private var entries: [CoverLetterEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var opened: CoverLetterEntry?

    private var layout: Layout { Layout(rawValue: layoutRaw) ?? .list }
    private var sort: CoverLetterSort { CoverLetterSort(rawValue: sortRaw) ?? .newest }

    /// Search narrows what's loaded, on the device: every word has to appear
    /// in the role, the company or the letter.
    private var shown: [CoverLetterEntry] {
        let words = searchText.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let haystack = "\(entry.title) \(entry.company) \(entry.text) \(entry.preview)".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .searchable(text: $searchText, prompt: "Search letters, roles, companies")
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .padding(8)
                    .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .padding()
                    .onTapGesture { self.errorMessage = nil }
            }
        }
        .task(id: "\(sortRaw)-\(source.rawValue)") { await load() }
        .refreshable { await load() }
        .refreshButton("Refresh the cover letter library", isRefreshing: isLoading) { await load() }
        .sheet(item: $opened) { entry in
            CoverLetterDetailView(client: client, entry: entry, onUnauthorized: onUnauthorized)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Sort by", selection: $sortRaw) {
                    ForEach(CoverLetterSort.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(sort.label, systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort by \(sort.label)")

            Menu {
                Picker("Show", selection: $source) {
                    ForEach(CoverLetterSource.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(source.label, systemImage: "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Showing \(source.label)")

            Spacer(minLength: 0)

            Picker("Layout", selection: $layoutRaw) {
                Label("List", systemImage: "list.bullet").tag(Layout.list.rawValue)
                Label("Grid", systemImage: "square.grid.2x2").tag(Layout.grid.rawValue)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .fixedSize()
            .accessibilityLabel("Show as a \(layout == .list ? "list" : "grid")")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && entries.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if shown.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No cover letters yet" : "No letters match",
                systemImage: "doc.text",
                description: Text(searchText.isEmpty
                    ? "Letters WORKS(c)OUT writes when you apply, and ones you upload in Identity, are kept here."
                    : "Try fewer or different words.")
            )
        } else if layout == .grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    ForEach(shown) { entry in
                        Button { opened = entry } label: { LetterCard(entry: entry) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the letter")
                    }
                }
                .padding()
            }
        } else {
            List(shown) { entry in
                Button { opened = entry } label: { LetterRow(entry: entry) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the letter")
            }
            .listStyle(.inset)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await client.fetchCoverLetters(sort: sort, source: source)
            errorMessage = nil
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch WorksCoutAPIError.notFound {
            errorMessage = "The library needs the latest server update."
        } catch {
            errorMessage = "Couldn't load your cover letters: \(error)"
        }
    }
}

// MARK: - Rows and cards

/// Where a letter is kept and whether WORKS(c)OUT wrote it, as small badges.
private struct LetterBadges: View {
    let entry: CoverLetterEntry

    var body: some View {
        HStack(spacing: 6) {
            badge(entry.isGenerated ? "Written for you" : "Uploaded",
                  systemImage: entry.isGenerated ? "sparkles" : "square.and.arrow.up")
            if entry.isInApp {
                badge("In app", systemImage: "iphone")
            }
            if entry.isInDrive {
                badge("Drive", systemImage: "externaldrive")
            }
        }
    }

    private func badge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

private struct LetterRow: View {
    let entry: CoverLetterEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title.isEmpty ? "Cover letter" : entry.title).font(.headline)
                Spacer()
                Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.company.isEmpty || !entry.status.isEmpty {
                Text([entry.company, entry.status].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !entry.preview.isEmpty {
                Text(entry.preview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            LetterBadges(entry: entry)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct LetterCard: View {
    let entry: CoverLetterEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title.isEmpty ? "Cover letter" : entry.title)
                .font(.headline)
                .lineLimit(2)
            if !entry.company.isEmpty {
                Text(entry.company).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().year())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.preview.isEmpty ? "Open to read" : entry.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .frame(maxHeight: .infinity, alignment: .top)
            LetterBadges(entry: entry)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.2)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

/// One letter: the full text for letters written here, with copy and share,
/// and the file itself from the app or from Drive.
struct CoverLetterDetailView: View {
    let client: WorksCoutAPIClient
    let entry: CoverLetterEntry
    let onUnauthorized: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var previewURL: URL?
    @State private var isDownloading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !entry.company.isEmpty || !entry.status.isEmpty {
                        Text([entry.company, entry.status].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.createdAt, format: .dateTime.month(.wide).day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LetterBadges(entry: entry)
                    actions
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    Divider()
                    if !entry.text.isEmpty {
                        Text(entry.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(entry.preview.isEmpty ? "Open the file to read this letter." : entry.preview + "…")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .navigationTitle(entry.title.isEmpty ? "Cover letter" : entry.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .quickLookPreview($previewURL)
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actionButtons }
            VStack(alignment: .leading, spacing: 8) { actionButtons }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if !entry.text.isEmpty {
            Button {
                copy(entry.text)
                message = "Copied."
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            ShareLink(item: entry.text, subject: Text(entry.title)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
        }
        if entry.isInApp, let url = URL(string: entry.fileUrl) {
            Button {
                Task { await openFile(url) }
            } label: {
                if isDownloading { ProgressView() } else { Label("Open file", systemImage: "doc.richtext") }
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .disabled(isDownloading)
        }
        if entry.isInDrive, let url = URL(string: entry.driveUrl) {
            Button {
                openURL(url)
            } label: {
                Label("Open in Drive", systemImage: "externaldrive")
            }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
        }
    }

    /// Downloaded through the account's token into a temporary file, then
    /// shown with Quick Look — the file link itself needs the token, so it
    /// can't just be opened in a browser.
    private func openFile(_ url: URL) async {
        isDownloading = true
        defer { isDownloading = false }
        do {
            let data = try await client.downloadFile(from: url)
            let ext = data.starts(with: Data("%PDF".utf8)) ? "pdf" : "docx"
            let safeTitle = entry.title.replacingOccurrences(of: "/", with: "-")
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeTitle.isEmpty ? "Cover letter" : safeTitle).\(ext)")
            try data.write(to: file, options: .atomic)
            previewURL = file
            message = nil
        } catch WorksCoutAPIError.notAuthenticated {
            onUnauthorized()
        } catch WorksCoutAPIError.notFound {
            message = entry.isInDrive ? "This one is kept in Google Drive — open it there." : "That file isn't available."
        } catch {
            message = "Couldn't open the file: \(error)"
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
