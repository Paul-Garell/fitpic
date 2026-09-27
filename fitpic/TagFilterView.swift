import SwiftUI

// MARK: - TagFilterView

/// A sheet listing every fit pic that carries a given tag, sorted newest first.
/// Presented when a display TagChip is tapped anywhere in the app.
/// Reuses FitPicCell (with its full date header) and supports delete + edit tags.
struct TagFilterView: View {

    @EnvironmentObject private var store: FitPicStore
    @Environment(\.dismiss) private var dismiss

    let tag: String

    @State private var editingFitPic: FitPic? = nil

    /// Live list of pics with this tag, recomputed as the store changes.
    private var pics: [FitPic] {
        store.fitPicsWithTag(tag)
    }

    var body: some View {
        NavigationStack {
            Group {
                if pics.isEmpty {
                    ContentUnavailableView(
                        "No fits tagged \u{201C}\(tag)\u{201D}",
                        systemImage: "tag"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(pics) { fitPic in
                                FitPicCell(
                                    fitPic: fitPic,
                                    onDelete: {
                                        ImageStorage.shared.delete(path: fitPic.imagePath)
                                        store.delete(fitPic)
                                    },
                                    onEditTags: { editingFitPic = fitPic }
                                )
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("#\(tag)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingFitPic) { fitPic in
                TagFilterEditTagsView(fitPic: fitPic) { updated in
                    store.update(updated)
                }
            }
            // Close automatically if no pics carry this tag anymore.
            .onChange(of: pics.isEmpty) { _, isEmpty in
                if isEmpty { dismiss() }
            }
            .tagFilterable()
        }
    }
}

// MARK: - Edit-tags adapter

private struct TagFilterEditTagsView: View {
    let fitPic: FitPic
    var onSave: (FitPic) -> Void

    @State private var tags: [String]
    @Environment(\.dismiss) private var dismiss

    init(fitPic: FitPic, onSave: @escaping (FitPic) -> Void) {
        self.fitPic = fitPic
        self.onSave = onSave
        _tags = State(initialValue: fitPic.tags)
    }

    var body: some View {
        AddTagsView(tags: $tags) {
            var updated = fitPic
            updated.tags = tags
            onSave(updated)
            dismiss()
        }
    }
}

#Preview {
    TagFilterView(tag: "Casual")
        .environmentObject(FitPicStore())
}
