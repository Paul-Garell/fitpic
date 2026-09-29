import Foundation
import FoundationModels

// MARK: - Generable schema
//
// These types are the contract between the app and the language model.
// Guided generation constrains the model's output to exactly these shapes,
// so every field here is also a tuning knob: descriptions, enum cases and
// ranges all change what the model produces. Keep them short — every
// description is serialized into the prompt and costs context tokens.
//
// Marked `nonisolated` so they're usable off the main actor (the target
// defaults to MainActor isolation).

@Generable
nonisolated enum GarmentCategory: String, Codable, CaseIterable, Sendable {
    case top
    case outerwear
    case bottom
    case dress
    case shoes
    case bag
    case hat
    case accessory
    case other

    var symbolName: String {
        switch self {
        case .top:       return "tshirt"
        case .outerwear: return "cloud.snow"
        case .bottom:    return "figure.walk"
        case .dress:     return "figure.dress.line.vertical.figure"
        case .shoes:     return "shoe"
        case .bag:       return "bag"
        case .hat:       return "graduationcap"
        case .accessory: return "eyeglasses"
        case .other:     return "questionmark.square"
        }
    }
}

@Generable
nonisolated enum GarmentPattern: String, Codable, CaseIterable, Sendable {
    case solid
    case striped
    case checked
    case floral
    case graphic
    case logo
    case textured
    case other
}

/// Approximate bounding box on a 0–1000 grid (top-left origin), so the model
/// doesn't need to know the real pixel size of the image.
@Generable
nonisolated struct GarmentBox: Codable, Equatable, Sendable {
    @Guide(description: "Left edge, 0-1000 of image width", .range(0...1000))
    var x: Int
    @Guide(description: "Top edge, 0-1000 of image height", .range(0...1000))
    var y: Int
    @Guide(description: "Width, 0-1000 of image width", .range(0...1000))
    var width: Int
    @Guide(description: "Height, 0-1000 of image height", .range(0...1000))
    var height: Int
}

@Generable
nonisolated struct DetectedGarment: Codable, Equatable, Sendable {
    @Guide(description: "Short specific name, e.g. 'navy crewneck sweater'")
    var name: String

    var category: GarmentCategory

    @Guide(description: "Main color in one or two words")
    var primaryColor: String

    @Guide(description: "Second most visible color, or 'none'")
    var secondaryColor: String

    var pattern: GarmentPattern

    @Guide(description: "Likely material, e.g. denim, cotton, leather, knit, or 'unknown'")
    var material: String

    @Guide(description: "Distinguishing details: logos, graphics, fit, length, closures")
    var details: String

    @Guide(description: "Approximate location of this item in the image")
    var box: GarmentBox

    @Guide(description: "Confidence this item is really present, 0-100", .range(0...100))
    var confidence: Int
}

@Generable
nonisolated struct OutfitAnalysis: Codable, Equatable, Sendable {
    @Guide(description: "Each distinct clothing item, shoe, bag and accessory the person wears", .maximumCount(10))
    var items: [DetectedGarment]
}

/// Output of the optional LLM re-rank stage. `reason` comes first so the
/// model "thinks" before committing to an index.
@Generable
nonisolated struct MatchDecision: Codable, Equatable, Sendable {
    @Guide(description: "One short sentence comparing the detected item to the candidates")
    var reason: String

    @Guide(description: "Index of the candidate that is the SAME physical item, or -1 if none", .range(-1...9))
    var matchIndex: Int
}
