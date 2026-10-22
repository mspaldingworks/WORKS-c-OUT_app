import MapKit
import SwiftUI

/// Where job distances are measured from: type a city or ZIP, pick the match.
///
/// A sheet rather than a field inside the Identity list, because the inline
/// version hid its own text field — the only obvious control was a greyed-out
/// "Set" button that did nothing until something had been typed. Matches come
/// from MapKit's search on the device, so the server never sends an address
/// to a third party; it only ever stores the chosen point and its label.
struct HomeLocationSheet: View {
    struct Choice {
        let label: String
        let latitude: Double
        let longitude: Double
    }

    let initialQuery: String
    let onPick: (Choice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var matches: [Match] = []
    @State private var isSearching = false
    @State private var message: String?
    @FocusState private var fieldFocused: Bool

    init(initialQuery: String = "", onPick: @escaping (Choice) -> Void) {
        self.initialQuery = initialQuery
        self.onPick = onPick
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("City and state, or ZIP code", text: $query)
                            .focused($fieldFocused)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textContentType(.addressCityAndState)
                            .submitLabel(.search)
                            #endif
                            .onSubmit { Task { await search() } }
                        if isSearching {
                            ProgressView()
                        }
                    }
                    Button {
                        Task { await search() }
                    } label: {
                        Label("Find", systemImage: "magnifyingglass")
                    }
                    .frame(minHeight: 44)
                    .disabled(trimmed.isEmpty || isSearching)
                } footer: {
                    Text("Only the point on the map and the place name you pick are saved. Distances to each job are measured from here.")
                }

                if let message {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                    }
                }

                if !matches.isEmpty {
                    Section("Pick your location") {
                        ForEach(matches) { match in
                            Button {
                                onPick(Choice(label: match.label, latitude: match.latitude,
                                              longitude: match.longitude))
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.label).foregroundStyle(.primary)
                                    if !match.detail.isEmpty {
                                        Text(match.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Sets this as your home location")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Home location")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { fieldFocused = true }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func search() async {
        let text = trimmed
        guard !text.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        message = nil

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        do {
            let response = try await MKLocalSearch(request: request).start()
            matches = Self.unique(response.mapItems.prefix(8).map(Match.init))
            if matches.isEmpty {
                message = "Nothing found for \(text). Try a city and state, or a ZIP code."
            }
        } catch {
            matches = []
            message = "Couldn't find \(text). Check the spelling, or try a ZIP code."
        }
    }

    /// The same city often comes back more than once; show it once.
    private static func unique(_ matches: [Match]) -> [Match] {
        var seen = Set<String>()
        return matches.filter { seen.insert($0.label).inserted }
    }

    struct Match: Identifiable {
        let id = UUID()
        let label: String
        let detail: String
        let latitude: Double
        let longitude: Double

        /// "Louisville, KY 40205" rather than whatever was typed, so it's
        /// clear the search understood.
        init(_ item: MKMapItem) {
            let placemark = item.placemark
            let cityState = [placemark.locality, placemark.administrativeArea]
                .compactMap { $0 }
                .joined(separator: ", ")
            let parts = [cityState, placemark.postalCode ?? ""].filter { !$0.isEmpty }
            label = parts.isEmpty ? (item.name ?? "Selected place") : parts.joined(separator: " ")
            detail = placemark.country ?? ""
            latitude = placemark.coordinate.latitude
            longitude = placemark.coordinate.longitude
        }
    }
}
