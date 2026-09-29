import SwiftUI

// MARK: - ClosetView

/// Closet tab: every cataloged item grouped by category, plus entry to the Lab.
struct ClosetView: View {

    @EnvironmentObject private var closet: ClosetStore
    @EnvironmentObject private var fitPicStore: FitPicStore

    @State private var showLab = false
    @State private var showSettings = false
    @State private var confirmDeleteAll = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if closet.items.isEmpty {
                    emptyState
                } else {
                    itemGrid
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Closet")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showLab = true } label: {
                        Label("Lab", systemImage: "flask")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showSettings = true } label: {
                            Label("Pipeline settings", systemImage: "slider.horizontal.3")
                        }
                        Button(role: .destructive) { confirmDeleteAll = true } label: {
                            Label("Delete all items", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ladybug")
                    }
                    .accessibilityLabel("Debug menu")
                }
            }
            .sheet(isPresented: $showLab) { ClosetLabView() }
            .sheet(isPresented: $showSettings) { ClosetDebugSettingsView() }
            .confirmationDialog("Delete every closet item?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete all \(closet.items.count) items", role: .destructive) { closet.deleteAll() }
            } message: {
                Text("Fit pics are not affected. This cannot be undone.")
            }
            .onAppear {
                closet.pruneWornOn(validFitPicIDs: Set(fitPicStore.fitPics.map(\.id)))
            }
        }
    }

    private var itemGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("\(closet.items.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ForEach(GarmentCategory.allCases, id: \.self) { category in
                    let items = closet.items(in: category)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("\(category.rawValue.capitalized) (\(items.count))", systemImage: category.symbolName)
                                .font(.headline)
                                .padding(.horizontal)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(items.sorted { $0.wornOn.count > $1.wornOn.count }) { item in
                                    NavigationLink {
                                        ClosetItemDetailView(itemID: item.id)
                                    } label: {
                                        ClosetItemTile(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No items yet", systemImage: "hanger")
        } description: {
            Text("Run the pipeline on a fit pic in the Lab, review the guesses, and commit them.")
        } actions: {
            Button("Open Lab") { showLab = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - ClosetItemTile

struct ClosetItemTile: View {
    let item: ClosetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let path = item.thumbnailPath {
                    AsyncStoredImage(path: path, targetWidth: 104)
                        .scaledToFit()
                } else {
                    Image(systemName: item.category.symbolName)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
            Text("worn \(item.wornOn.count)× · \(item.featurePrints.count) prints")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
