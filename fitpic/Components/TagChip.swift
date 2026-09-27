import SwiftUI

// MARK: - TagChip

/// A small pill-shaped label used throughout the app for displaying tags.
///
/// Behavior:
/// - When `isRemovable` is true, a close button is shown and the chip is treated as
///   a composition control (not a navigation trigger).
/// - Otherwise, if an `onTagTapped` action is present in the environment and
///   `interactive` is true, tapping the chip invokes it (e.g. to open a tag filter).
struct TagChip: View {
    let label: String
    var isRemovable: Bool = false
    /// Set false to render a plain, non-tappable chip even when an environment action exists.
    var interactive: Bool = true
    var onRemove: (() -> Void)? = nil

    @Environment(\.onTagTapped) private var onTagTapped

    private var isTappable: Bool {
        interactive && !isRemovable && onTagTapped != nil
    }

    var body: some View {
        Group {
            if isTappable {
                Button { onTagTapped?(label) } label: { chipBody }
                    .buttonStyle(.plain)
            } else {
                chipBody
            }
        }
    }

    private var chipBody: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)

            if isRemovable {
                Button(action: { onRemove?() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.12))
        .foregroundStyle(Color.blue)
        .clipShape(Capsule())
    }
}
