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

    private var todaysPics: [FitPic] {
        store.fitPicsForDate(Date())
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            feedContent

            if !todaysPics.isEmpty {
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
        if todaysPics.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 20) {
                    Color.clear.frame(height: 52)   // clears the floating add button
                    ForEach(todaysPics) { fitPic in
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
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
        }
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
