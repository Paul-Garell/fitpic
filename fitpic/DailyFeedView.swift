import SwiftUI

// MARK: - DailyFeedView

/// Root view for the Daily Feed tab.
///
/// States:
///   • No pics today  → centered large "+" prompt.
///   • Has pics today → scrollable list of FitPicCells + floating top-right "+" button.
///
/// Flow: CameraView (owns capture + review + tag entry) → onComplete → save → feed updates.
struct DailyFeedView: View {

    @StateObject private var store = FitPicStore()
    @State private var showCamera = false
    @State private var editingFitPic: FitPic? = nil

    /// Fit pics grouped by day, newest day first.
    private var sections: [(day: Date, pics: [FitPic])] {
        store.groupedByDay
    }

    private var hasPics: Bool { !store.fitPics.isEmpty }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            feedContent

            if hasPics {
                addButton
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView(
                onComplete: { image, tags in
                    showCamera = false
                    saveNewFitPic(image: image, tags: tags)
                },
                onDismiss: { showCamera = false }
            )
        }
        .sheet(item: $editingFitPic) { fitPic in
            EditTagsView(fitPic: fitPic) { updated in
                store.update(updated)
            }
        }
    }

    // MARK: Feed content

    @ViewBuilder
    private var feedContent: some View {
        if !hasPics {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                    Color.clear.frame(height: 52)   // clears the floating add button

                    ForEach(sections, id: \.day) { section in
                        Section {
                            ForEach(section.pics) { fitPic in
                                FitPicCell(
                                    fitPic: fitPic,
                                    showsDate: false,   // day is shown in the section header
                                    onDelete: {
                                        ImageStorage.shared.delete(path: fitPic.imagePath)
                                        store.delete(fitPic)
                                    },
                                    onEditTags: { editingFitPic = fitPic }
                                )
                            }
                        } header: {
                            sectionHeader(for: section.day)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: Section header

    private func sectionHeader(for day: Date) -> some View {
        Text(dayLabel(for: day))
            .font(.title3)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
    }

    /// "Today", "Yesterday", or a full date like "September 25, 2026".
    private func dayLabel(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Button { showCamera = true } label: {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 140, height: 140)
                    Image(systemName: "plus")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(Color.blue)
                }
            }
            .buttonStyle(.plain)

            Text("Add today's fit")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Add button (top-right, shown when pics exist)

    private var addButton: some View {
        Button { showCamera = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.blue)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        }
    }

    // MARK: Save

    private func saveNewFitPic(image: UIImage, tags: [String]) {
        Task(priority: .userInitiated) {
            await persistFitPic(image: image, tags: tags)
        }
    }

    private func persistFitPic(image: UIImage, tags: [String]) async {
        let path: String? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: ImageStorage.shared.save(image))
            }
        }
        guard let path else { return }
        store.add(FitPic(imagePath: path, tags: tags))
    }
}

// MARK: - EditTagsView

/// Thin adapter that feeds an existing FitPic's tags into AddTagsView for editing.
private struct EditTagsView: View {

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

// MARK: - Preview

#Preview {
    DailyFeedView()
}
