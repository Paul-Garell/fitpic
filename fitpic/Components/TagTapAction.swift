import SwiftUI

// MARK: - TagTapAction

/// An action invoked when a display TagChip is tapped, carrying the tag label.
/// Injected via the environment so any TagChip in the hierarchy can trigger it
/// without threading callbacks through every intermediate view.
struct TagTapAction {
    let handler: (String) -> Void

    func callAsFunction(_ tag: String) {
        handler(tag)
    }
}

private struct TagTapActionKey: EnvironmentKey {
    static let defaultValue: TagTapAction? = nil
}

extension EnvironmentValues {
    var onTagTapped: TagTapAction? {
        get { self[TagTapActionKey.self] }
        set { self[TagTapActionKey.self] = newValue }
    }
}

extension View {
    /// Makes every display TagChip below this view tappable, invoking `action` with the tag.
    func onTagTapped(_ action: @escaping (String) -> Void) -> some View {
        environment(\.onTagTapped, TagTapAction(handler: action))
    }

    /// Convenience: makes TagChips below tappable and presents a TagFilterView sheet
    /// for the tapped tag. Manages its own selection state.
    func tagFilterable() -> some View {
        modifier(TagFilterableModifier())
    }
}

// MARK: - TagFilterableModifier

/// Adds tag-tap handling plus a TagFilterView sheet to any view showing TagChips.
private struct TagFilterableModifier: ViewModifier {
    @State private var selectedTag: SelectedTag? = nil

    func body(content: Content) -> some View {
        content
            .onTagTapped { tag in
                selectedTag = SelectedTag(tag: tag)
            }
            .sheet(item: $selectedTag) { selection in
                TagFilterView(tag: selection.tag)
            }
    }

    private struct SelectedTag: Identifiable {
        let tag: String
        var id: String { tag }
    }
}
