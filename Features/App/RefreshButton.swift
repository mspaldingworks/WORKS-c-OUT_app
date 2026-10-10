import SwiftUI

extension View {
    /// Adds a Refresh button to the toolbar.
    ///
    /// Pull-to-refresh already reloads each section on the phone, but there is
    /// nothing to pull on the Mac and the gesture is easy to miss, so every
    /// section gets a button that does the same thing. ⌘R with a keyboard.
    ///
    /// The list stays on screen while it reloads; only the button changes, to
    /// a spinner, so a tap visibly did something.
    ///
    /// - Parameters:
    ///   - label: What VoiceOver reads, naming the section ("Refresh the job feed").
    ///   - isRefreshing: True while a reload is in flight.
    ///   - action: The same reload the section's `.refreshable` runs.
    func refreshButton(
        _ label: String,
        isRefreshing: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await action() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh")
                .accessibilityLabel(label)
            }
        }
    }
}
