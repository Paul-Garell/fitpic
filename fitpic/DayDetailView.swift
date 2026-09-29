import SwiftUI

// MARK: - DayDetailView

/// Full-size, scrollable view of every fit pic taken on a given day.
/// Presented as a sheet from the calendar. Supports delete and tag editing,
/// mirroring the daily feed's cell behavior.
struct DayDetailView: View {

    @EnvironmentObject private var store: FitPicStore
    @Environment(\.dismiss) private var dismiss

    let day: Date

    @State private var editingFitPic: FitPic? = nil
    @State private var catalogingFitPic: FitPic? = nil

    /// Live list of the day's pics, newest first — recomputed as the store changes.
    private var pics: [FitPic] {
        store.fitPicsForDate(day)
    }

    var body: some View {
        NavigationStack {
            Group {
                if pics.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(pics) { fitPic in
                                FitPicCell(
                                    fitPic: fitPic,
                                    showsDate: false,   // the day is in the nav title
                                    onDelete: {
                                        ImageStorage.shared.delete(path: fitPic.imagePath)
                                        store.delete(fitPic)
                                    },
                                    onEditTags: { editingFitPic = fitPic },
                                    onCatalog: { catalogingFitPic = fitPic }
                                )
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingFitPic) { fitPic in
                DayEditTagsView(fitPic: fitPic) { updated in
                    store.update(updated)
                }
            }
            .sheet(item: $catalogingFitPic) { fitPic in
                ClosetLabView(initialFitPic: fitPic)
            }
            // If the last pic for the day is deleted, close the sheet.
            .onChange(of: pics.isEmpty) { _, isEmpty in
                if isEmpty { dismiss() }
            }
            .tagFilterable()
        }
    }

    private var titleText: String {
        day.formatted(.dateTime.weekday(.abbreviated).month(.wide).day())
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No fits this day",
            systemImage: "photo.on.rectangle.angled"
        )
    }
}

// MARK: - DayEditTagsView

/// Adapter that feeds an existing FitPic's tags into AddTagsView for editing.
private struct DayEditTagsView: View {

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
    DayDetailView(day: Date())
        .environmentObject(FitPicStore())
}
