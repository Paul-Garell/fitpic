import SwiftUI

// MARK: - TagChip

/// A small pill-shaped label used throughout the app for displaying tags.
/// When `isRemovable` is true, a close button is rendered inside the chip.
struct TagChip: View {
    let label: String
    var isRemovable: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
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
