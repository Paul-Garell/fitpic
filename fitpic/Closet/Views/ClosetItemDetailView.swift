import SwiftUI
import Vision

// MARK: - ClosetItemDetailView

/// Item attributes, wear history, and a debug table of distances to every
/// other item — the quickest way to calibrate the match threshold.
struct ClosetItemDetailView: View {

    let itemID: UUID

    @EnvironmentObject private var closet: ClosetStore
    @EnvironmentObject private var fitPicStore: FitPicStore
    @EnvironmentObject private var settingsStore: ClosetDebugSettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var editedName = ""
    @State private var confirmDelete = false

    private var item: ClosetItem? { closet.item(id: itemID) }

    var body: some View {
        Group {
            if let item {
                content(for: item)
            } else {
                ContentUnavailableView("Item deleted", systemImage: "trash")
            }
        }
        .navigationTitle(item?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(for item: ClosetItem) -> some View {
        List {
            Section {
                if let path = item.thumbnailPath {
                    AsyncStoredImage(path: path, targetWidth: 240)
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                }
                TextField("Name", text: $editedName)
                    .onAppear { editedName = item.name }
                    .onSubmit {
                        var updated = item
                        updated.name = editedName
                        closet.update(updated)
                    }
            }

            Section("Attributes") {
                LabeledContent("Category", value: item.category.rawValue)
                LabeledContent("Color", value: "\(item.primaryColor) / \(item.secondaryColor)")
                LabeledContent("Pattern", value: item.pattern.rawValue)
                LabeledContent("Material", value: item.material)
                if !item.details.isEmpty {
                    Text(item.details).font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Debug") {
                LabeledContent("ID", value: item.id.uuidString.prefix(8) + "…")
                LabeledContent("Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Feature prints", value: "\(item.featurePrints.count)/\(ClosetItem.maxFeaturePrints)")
                if item.featurePrints.count > 1 {
                    LabeledContent("Self-distance (max)", value: selfDistance(item).map(ClosetMatcher.fmt) ?? "n/a")
                }
                Text(item.summary).font(.caption2.monospaced()).textSelection(.enabled)
            }

            wornInSection(item)
            distancesSection(item)

            Section {
                Button("Delete item", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("Delete \(item.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                closet.delete(item)
                dismiss()
            }
        }
    }

    // MARK: Worn in

    @ViewBuilder
    private func wornInSection(_ item: ClosetItem) -> some View {
        let pics = fitPicStore.allSorted.filter { item.wornOn.contains($0.id) }
        Section("Worn in (\(pics.count))") {
            if pics.isEmpty {
                Text("Not linked to any fit pic").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pics) { pic in
                            VStack(spacing: 2) {
                                AsyncStoredImage(path: pic.imagePath, targetWidth: 70)
                                    .frame(width: 70, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(pic.date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Distances

    /// Largest distance between this item's own prints — how much the same
    /// item varies across photos. The threshold should sit above this.
    private func selfDistance(_ item: ClosetItem) -> Double? {
        var maxDistance: Double?
        for i in item.featurePrints.indices {
            for j in item.featurePrints.indices where j > i {
                if let d = try? item.featurePrints[i].distance(to: item.featurePrints[j]) {
                    maxDistance = max(maxDistance ?? 0, d)
                }
            }
        }
        return maxDistance
    }

    @ViewBuilder
    private func distancesSection(_ item: ClosetItem) -> some View {
        let settings = settingsStore.settings
        let rows: [(ClosetItem, Double?, Double, Double)] = closet.items
            .filter { $0.id != item.id }
            .map { other in
                let fd: Double? = item.featurePrints.flatMap { a in
                    other.featurePrints.compactMap { b in try? a.distance(to: b) }
                }.min()
                let attrs = ClosetMatcher.attributeScore(.init(item), .init(other))
                let combined = ClosetMatcher.combinedScore(
                    featureDistance: fd, attributePenalty: attrs.penalty, attributeWeight: settings.attributeWeight
                )
                return (other, fd, attrs.penalty, combined)
            }
            .sorted { $0.3 < $1.3 }

        Section {
            if rows.isEmpty {
                Text("No other items").foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.0.id) { other, fd, attr, combined in
                HStack {
                    Image(systemName: combined <= settings.matchThreshold ? "exclamationmark.triangle.fill" : "checkmark")
                        .foregroundStyle(combined <= settings.matchThreshold ? .orange : .green)
                    VStack(alignment: .leading) {
                        Text(other.name).font(.caption)
                        Text("\(other.category.rawValue) · fd \(fd.map(ClosetMatcher.fmt) ?? "n/a") · attr \(ClosetMatcher.fmt(attr))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(ClosetMatcher.fmt(combined)).font(.caption.monospacedDigit())
                }
            }
        } header: {
            Text("Distance to other items")
        } footer: {
            Text("⚠️ = would be confused with this item at the current threshold (\(ClosetMatcher.fmt(settings.matchThreshold))). Category is not filtered here.")
        }
    }
}
