import Foundation
import Combine

// MARK: - Settings enums

nonisolated enum DetectionBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case onDevice
    case privateCloud
    /// Replays `mockResponseJSON` instead of calling a model. Lets you tune
    /// crops/matching on the simulator, or re-run downstream stages against a
    /// response captured on device (copy stage 4's "raw response JSON").
    case mock

    var id: String { rawValue }
    var label: String {
        switch self {
        case .onDevice:     return "On-device (SystemLanguageModel)"
        case .privateCloud: return "Private Cloud Compute"
        case .mock:         return "Mock (replay JSON)"
        }
    }
}

nonisolated enum PreprocessBackground: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Keep alpha. Note: some model paths may flatten transparency to black.
    case transparent
    /// Composite the segmented person over white.
    case white
    /// Composite over mid-grey (useful for white garments).
    case grey

    var id: String { rawValue }
}

nonisolated enum CropStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Use the bounding box the LLM returned.
    case modelBox
    /// Derive a region from Vision body-pose joints based on garment category.
    case bodyPose
    /// Use the whole (segmented) person for every item.
    case fullPerson

    var id: String { rawValue }
}

nonisolated enum ReasoningChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, light, moderate, deep
    var id: String { rawValue }
}

// MARK: - ClosetDebugSettings

/// Every tunable knob in the cataloging pipeline. A snapshot is stored
/// with each run so traces are reproducible.
nonisolated struct ClosetDebugSettings: Codable, Equatable, Sendable {

    // Stage: normalize
    var maxImageDimension: Int = 1024

    // Stage: segmentation
    var segmentPerson: Bool = true
    var background: PreprocessBackground = .white

    // Stage: detection (LLM)
    var backend: DetectionBackend = .onDevice
    var useContentTaggingUseCase: Bool = false
    var greedySampling: Bool = true
    var temperature: Double = 0.3
    var maxResponseTokens: Int = 1500
    var includeSchemaInPrompt: Bool = true
    var reasoning: ReasoningChoice = .none   // Private Cloud Compute only
    var instructions: String = ClosetDebugSettings.defaultInstructions
    var prompt: String = ClosetDebugSettings.defaultPrompt
    var minimumConfidence: Int = 30
    var mockResponseJSON: String = ClosetDebugSettings.defaultMockResponseJSON

    // Stage: crops
    var cropStrategy: CropStrategy = .bodyPose
    var cropPadding: Double = 0.06
    var minimumJointConfidence: Double = 0.3

    // Stage: matching
    var requireSameCategory: Bool = true
    /// Weight of attribute mismatch vs. feature-print distance in the combined score.
    var attributeWeight: Double = 0.35
    /// Combined score at or below this counts as a match.
    var matchThreshold: Double = 0.55

    // Stage: LLM re-rank
    var useLLMRerank: Bool = false
    var rerankTopK: Int = 3
    var rerankIncludeImages: Bool = true

    // MARK: Defaults

    init() {}

    /// Tolerant decoding: any key missing from saved data (e.g. a knob added
    /// after the settings were persisted) falls back to its default instead of
    /// discarding the whole saved configuration.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClosetDebugSettings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        maxImageDimension = v(.maxImageDimension, d.maxImageDimension)
        segmentPerson = v(.segmentPerson, d.segmentPerson)
        background = v(.background, d.background)
        backend = v(.backend, d.backend)
        useContentTaggingUseCase = v(.useContentTaggingUseCase, d.useContentTaggingUseCase)
        greedySampling = v(.greedySampling, d.greedySampling)
        temperature = v(.temperature, d.temperature)
        maxResponseTokens = v(.maxResponseTokens, d.maxResponseTokens)
        includeSchemaInPrompt = v(.includeSchemaInPrompt, d.includeSchemaInPrompt)
        reasoning = v(.reasoning, d.reasoning)
        instructions = v(.instructions, d.instructions)
        prompt = v(.prompt, d.prompt)
        minimumConfidence = v(.minimumConfidence, d.minimumConfidence)
        mockResponseJSON = v(.mockResponseJSON, d.mockResponseJSON)
        cropStrategy = v(.cropStrategy, d.cropStrategy)
        cropPadding = v(.cropPadding, d.cropPadding)
        minimumJointConfidence = v(.minimumJointConfidence, d.minimumJointConfidence)
        requireSameCategory = v(.requireSameCategory, d.requireSameCategory)
        attributeWeight = v(.attributeWeight, d.attributeWeight)
        matchThreshold = v(.matchThreshold, d.matchThreshold)
        useLLMRerank = v(.useLLMRerank, d.useLLMRerank)
        rerankTopK = v(.rerankTopK, d.rerankTopK)
        rerankIncludeImages = v(.rerankIncludeImages, d.rerankIncludeImages)
    }
    static let defaultInstructions = """
    You catalog clothing in outfit photos for a personal wardrobe app. \
    Only list items the person is actually wearing or carrying. \
    Never invent items that are not clearly visible. \
    Treat each physical garment as one item, even if partly hidden.
    """

    static let defaultPrompt = """
    List every clothing item, pair of shoes, bag and accessory worn by the person in this photo. \
    Use specific names that would help recognize the same item in a different photo.
    """

    static let defaultMockResponseJSON = """
    {"items":[
     {"name":"navy crewneck sweater","category":"top","primaryColor":"navy","secondaryColor":"none","pattern":"solid","material":"knit","details":"ribbed cuffs","box":{"x":250,"y":180,"width":500,"height":330},"confidence":90},
     {"name":"light wash straight jeans","category":"bottom","primaryColor":"light blue","secondaryColor":"none","pattern":"solid","material":"denim","details":"straight leg","box":{"x":280,"y":480,"width":440,"height":420},"confidence":85},
     {"name":"white leather sneakers","category":"shoes","primaryColor":"white","secondaryColor":"none","pattern":"solid","material":"leather","details":"low top","box":{"x":260,"y":880,"width":480,"height":110},"confidence":80}
    ]}
    """
}

// MARK: - Store

/// Persists the debug settings in UserDefaults and publishes changes.
final class ClosetDebugSettingsStore: ObservableObject {

    @Published var settings: ClosetDebugSettings {
        didSet { save() }
    }

    private let key = "closetDebugSettings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ClosetDebugSettings.self, from: data) {
            settings = decoded
        } else {
            settings = ClosetDebugSettings()
        }
    }

    func resetToDefaults() {
        settings = ClosetDebugSettings()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
