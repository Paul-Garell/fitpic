import Foundation
import Vision

// MARK: - ClosetMatcher

/// Scores a detected garment against existing closet items.
///
///     combined = (1 - attributeWeight) * featureDistance + attributeWeight * attributePenalty
///
/// Lower is better. `featureDistance` is the minimum Vision feature-print
/// distance across the item's stored prints; `attributePenalty` is a 0…1
/// mismatch score over color / pattern / material text.
nonisolated enum ClosetMatcher {

    struct AttributeScore: Equatable {
        let penalty: Double
        let notes: [String]
    }

    // Relative weights inside the attribute penalty (sum to 1).
    static let colorWeight = 0.5
    static let patternWeight = 0.3
    static let materialWeight = 0.2

    static func normalized(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 0 if equal, 0.3 if one contains the other ("navy" / "navy blue"),
    /// `unknownPenalty` if either side is unknown, else 1.
    static func textMismatch(_ a: String, _ b: String, unknownPenalty: Double = 0.5) -> Double {
        let x = normalized(a), y = normalized(b)
        if x == y { return 0 }
        if x.isEmpty || y.isEmpty || x == "unknown" || y == "unknown" { return unknownPenalty }
        if x.contains(y) || y.contains(x) { return 0.3 }
        return 1
    }

    /// The subset of attributes that participate in matching.
    struct Attributes: Equatable {
        let category: GarmentCategory
        let primaryColor: String
        let pattern: GarmentPattern
        let material: String

        init(category: GarmentCategory, primaryColor: String, pattern: GarmentPattern, material: String) {
            self.category = category
            self.primaryColor = primaryColor
            self.pattern = pattern
            self.material = material
        }

        init(_ garment: DetectedGarment) {
            self.init(category: garment.category, primaryColor: garment.primaryColor,
                      pattern: garment.pattern, material: garment.material)
        }

        init(_ item: ClosetItem) {
            self.init(category: item.category, primaryColor: item.primaryColor,
                      pattern: item.pattern, material: item.material)
        }
    }

    static func attributeScore(_ a: Attributes, _ b: Attributes) -> AttributeScore {
        if a.category != b.category {
            return AttributeScore(penalty: 1, notes: ["category \(a.category.rawValue)≠\(b.category.rawValue)"])
        }
        let color = textMismatch(a.primaryColor, b.primaryColor)
        let patternMismatch: Double = a.pattern == b.pattern ? 0 : 1
        let materialMismatch = textMismatch(a.material, b.material)

        let notes = [
            "color \(a.primaryColor)~\(b.primaryColor)=\(fmt(color))",
            "pattern \(a.pattern.rawValue)~\(b.pattern.rawValue)=\(fmt(patternMismatch))",
            "material \(a.material)~\(b.material)=\(fmt(materialMismatch))"
        ]
        let penalty = colorWeight * color + patternWeight * patternMismatch + materialWeight * materialMismatch
        return AttributeScore(penalty: penalty, notes: notes)
    }

    static func combinedScore(featureDistance: Double?, attributePenalty: Double, attributeWeight: Double) -> Double {
        guard let featureDistance else { return attributePenalty }
        let w = min(max(attributeWeight, 0), 1)
        return (1 - w) * featureDistance + w * attributePenalty
    }

    /// Ranks all eligible closet items for one detected garment.
    static func rank(
        garment: DetectedGarment,
        featurePrint: FeaturePrintObservation?,
        closet: [ClosetItem],
        settings: ClosetDebugSettings
    ) -> [MatchCandidate] {
        let eligible = settings.requireSameCategory
            ? closet.filter { $0.category == garment.category }
            : closet

        return eligible.map { item in
            var notes: [String] = []
            let distance: Double? = {
                guard let featurePrint, !item.featurePrints.isEmpty else { return nil }
                let distances = item.featurePrints.compactMap { try? featurePrint.distance(to: $0) }
                return distances.min()
            }()
            if distance == nil {
                notes.append(featurePrint == nil ? "no feature print for detection" : "item has no feature prints")
            }
            let attrs = attributeScore(Attributes(garment), Attributes(item))
            notes.append(contentsOf: attrs.notes)
            let combined = combinedScore(
                featureDistance: distance,
                attributePenalty: attrs.penalty,
                attributeWeight: settings.attributeWeight
            )
            return MatchCandidate(
                itemID: item.id,
                itemName: item.name,
                featureDistance: distance,
                attributePenalty: attrs.penalty,
                combinedScore: combined,
                passesThreshold: combined <= settings.matchThreshold,
                attributeNotes: notes
            )
        }
        .sorted { $0.combinedScore < $1.combinedScore }
    }

    static func fmt(_ value: Double) -> String { String(format: "%.2f", value) }
}
