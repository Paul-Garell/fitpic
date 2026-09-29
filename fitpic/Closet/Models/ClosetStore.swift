import Foundation
import Combine
import Vision

// MARK: - ClosetItem

/// A single physical garment the user owns. Built up over time as the
/// pipeline recognises it in more fit pics.
nonisolated struct ClosetItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var category: GarmentCategory
    var primaryColor: String
    var secondaryColor: String
    var pattern: GarmentPattern
    var material: String
    var details: String

    /// Relative path (via ImageStorage) to a representative crop.
    var thumbnailPath: String?

    /// One Vision feature print per confirmed sighting (capped). Matching uses
    /// the minimum distance across all of them, so the item gets easier to
    /// recognise the more often it's confirmed.
    var featurePrints: [FeaturePrintObservation]

    /// IDs of fit pics this item was confirmed in.
    var wornOn: [UUID]

    let createdAt: Date

    static let maxFeaturePrints = 8

    init(from garment: DetectedGarment, thumbnailPath: String?, featurePrint: FeaturePrintObservation?) {
        self.id = UUID()
        self.name = garment.name
        self.category = garment.category
        self.primaryColor = garment.primaryColor
        self.secondaryColor = garment.secondaryColor
        self.pattern = garment.pattern
        self.material = garment.material
        self.details = garment.details
        self.thumbnailPath = thumbnailPath
        self.featurePrints = featurePrint.map { [$0] } ?? []
        self.wornOn = []
        self.createdAt = Date()
    }

    /// Compact single-line description used in match prompts and debug output.
    var summary: String {
        var parts = ["\(name)", "category: \(category.rawValue)", "color: \(primaryColor)"]
        if secondaryColor.lowercased() != "none", !secondaryColor.isEmpty {
            parts.append("secondary: \(secondaryColor)")
        }
        parts.append("pattern: \(pattern.rawValue)")
        parts.append("material: \(material)")
        if !details.isEmpty { parts.append("details: \(details)") }
        return parts.joined(separator: "; ")
    }
}

extension DetectedGarment {
    var summary: String {
        var parts = ["\(name)", "category: \(category.rawValue)", "color: \(primaryColor)"]
        if secondaryColor.lowercased() != "none", !secondaryColor.isEmpty {
            parts.append("secondary: \(secondaryColor)")
        }
        parts.append("pattern: \(pattern.rawValue)")
        parts.append("material: \(material)")
        if !details.isEmpty { parts.append("details: \(details)") }
        return parts.joined(separator: "; ")
    }
}

// MARK: - ClosetStore

/// Persists the closet as JSON in Documents/closet.json.
/// (Not UserDefaults — feature prints make this too large for it.)
final class ClosetStore: ObservableObject {

    @Published private(set) var items: [ClosetItem] = []

    private let fileURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("closet.json")
    }()

    init() { load() }

    // MARK: Queries

    func item(id: UUID) -> ClosetItem? {
        items.first { $0.id == id }
    }

    func items(in category: GarmentCategory) -> [ClosetItem] {
        items.filter { $0.category == category }
    }

    func items(wornIn fitPicID: UUID) -> [ClosetItem] {
        items.filter { $0.wornOn.contains(fitPicID) }
    }

    // MARK: Mutations

    func add(_ item: ClosetItem) {
        items.append(item)
        save()
    }

    func update(_ item: ClosetItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        save()
    }

    func delete(_ item: ClosetItem) {
        if let path = item.thumbnailPath {
            ImageStorage.shared.delete(path: path)
        }
        items.removeAll { $0.id == item.id }
        save()
    }

    /// Records a confirmed sighting of an existing item.
    func recordSighting(itemID: UUID, fitPicID: UUID?, featurePrint: FeaturePrintObservation?) {
        guard var item = item(id: itemID) else { return }
        if let fitPicID, !item.wornOn.contains(fitPicID) {
            item.wornOn.append(fitPicID)
        }
        if let featurePrint {
            item.featurePrints.append(featurePrint)
            if item.featurePrints.count > ClosetItem.maxFeaturePrints {
                item.featurePrints.removeFirst(item.featurePrints.count - ClosetItem.maxFeaturePrints)
            }
        }
        update(item)
    }

    /// Drops references to fit pics that no longer exist.
    func pruneWornOn(validFitPicIDs: Set<UUID>) {
        var changed = false
        for index in items.indices {
            let before = items[index].wornOn.count
            items[index].wornOn.removeAll { !validFitPicIDs.contains($0) }
            changed = changed || before != items[index].wornOn.count
        }
        if changed { save() }
    }

    /// Debug: wipe the whole closet (thumbnails included).
    func deleteAll() {
        for item in items {
            if let path = item.thumbnailPath { ImageStorage.shared.delete(path: path) }
        }
        items = []
        save()
    }

    // MARK: Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[ClosetStore] save error: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = try JSONDecoder().decode([ClosetItem].self, from: data)
        } catch {
            print("[ClosetStore] load error: \(error)")
        }
    }
}
