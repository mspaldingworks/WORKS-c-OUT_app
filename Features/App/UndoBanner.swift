import SwiftUI

/// What was just removed, and how to put it back.
struct RemovedItem: Identifiable, Equatable {
    let id: Int
    let label: String
}

/// Undo instead of "are you sure?".
///
/// CLAUDE.md §3.5: confirmation dialogs get dismissed reflexively, so they
/// protect nothing; undo actually does. It also rules out auto-dismissing
/// toasts, so this stays until she acts on it — a banner that vanishes while
/// she's reading is the same trap as a dialog she didn't read.
struct UndoBanner: View {
    let removed: RemovedItem
    let isWorking: Bool
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Removed \(removed.label)")
                .font(.footnote)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: onUndo) {
                if isWorking { ProgressView() } else { Text("Undo").font(.footnote.weight(.semibold)) }
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .disabled(isWorking)
            .accessibilityLabel("Undo removing \(removed.label)")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Dismiss this message")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
