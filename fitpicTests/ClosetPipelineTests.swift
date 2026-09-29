import Testing
import Foundation
import CoreGraphics
import Vision
@testable import fitpic

// MARK: - Fixtures

private func garment(
    _ name: String = "navy crewneck sweater",
    category: GarmentCategory = .top,
    color: String = "navy",
    pattern: GarmentPattern = .solid,
    material: String = "knit",
    box: GarmentBox = GarmentBox(x: 100, y: 100, width: 500, height: 400)
) -> DetectedGarment {
    DetectedGarment(
        name: name, category: category, primaryColor: color, secondaryColor: "none",
        pattern: pattern, material: material, details: "", box: box, confidence: 90
    )
}

private func item(from g: DetectedGarment) -> ClosetItem {
    ClosetItem(from: g, thumbnailPath: nil, featurePrint: nil)
}

// MARK: - ClosetMatcher

@MainActor
struct ClosetMatcherTests {

    @Test func textMismatchLevels() {
        #expect(ClosetMatcher.textMismatch("Navy", " navy ") == 0)
        #expect(ClosetMatcher.textMismatch("navy", "navy blue") == 0.3)
        #expect(ClosetMatcher.textMismatch("unknown", "denim") == 0.5)
        #expect(ClosetMatcher.textMismatch("", "denim") == 0.5)
        #expect(ClosetMatcher.textMismatch("red", "green") == 1)
    }

    @Test func identicalAttributesHaveZeroPenalty() {
        let g = garment()
        let score = ClosetMatcher.attributeScore(.init(g), .init(item(from: g)))
        #expect(score.penalty == 0)
    }

    @Test func categoryMismatchIsMaxPenalty() {
        let score = ClosetMatcher.attributeScore(.init(garment(category: .top)), .init(garment(category: .bottom)))
        #expect(score.penalty == 1)
    }

    @Test func partialColorMatchIsWeighted() {
        let score = ClosetMatcher.attributeScore(.init(garment(color: "navy")), .init(garment(color: "navy blue")))
        #expect(abs(score.penalty - ClosetMatcher.colorWeight * 0.3) < 1e-9)
    }

    @Test func combinedScoreWeighting() {
        #expect(ClosetMatcher.combinedScore(featureDistance: nil, attributePenalty: 0.4, attributeWeight: 0.3) == 0.4)
        let c = ClosetMatcher.combinedScore(featureDistance: 0.6, attributePenalty: 0.2, attributeWeight: 0.25)
        #expect(abs(c - (0.75 * 0.6 + 0.25 * 0.2)) < 1e-9)
        // Weight is clamped to 0…1.
        #expect(ClosetMatcher.combinedScore(featureDistance: 0.6, attributePenalty: 0.2, attributeWeight: 5) == 0.2)
    }

    @Test func rankFiltersByCategoryAndSorts() {
        let detected = garment()
        let exact = item(from: garment("navy sweater"))
        let offColor = item(from: garment("red sweater", color: "red"))
        let jeans = item(from: garment("jeans", category: .bottom, color: "navy", material: "denim"))

        var settings = ClosetDebugSettings()
        settings.requireSameCategory = true
        settings.matchThreshold = 0.1

        let ranked = ClosetMatcher.rank(garment: detected, featurePrint: nil,
                                        closet: [offColor, jeans, exact], settings: settings)
        #expect(ranked.map(\.itemName) == ["navy sweater", "red sweater"])
        #expect(ranked[0].passesThreshold)
        #expect(!ranked[1].passesThreshold)
        #expect(ranked[0].featureDistance == nil)

        settings.requireSameCategory = false
        let all = ClosetMatcher.rank(garment: detected, featurePrint: nil,
                                     closet: [offColor, jeans, exact], settings: settings)
        #expect(all.count == 3)
        #expect(all.last?.itemName == "jeans")
    }
}

// MARK: - Crop heuristics

@MainActor
struct CropRectTests {

    let size = CGSize(width: 1000, height: 2000)

    @Test func fullPersonReturnsWholeImage() {
        let d = ClosetImaging.cropRect(for: garment(), strategy: .fullPerson, imageSize: size, joints: [:], padding: 0.1)
        #expect(d.rect == CGRect(origin: .zero, size: size))
    }

    @Test func modelBoxScalesFromThousandGrid() {
        let d = ClosetImaging.cropRect(
            for: garment(box: GarmentBox(x: 100, y: 250, width: 500, height: 250)),
            strategy: .modelBox, imageSize: size, joints: [:], padding: 0
        )
        #expect(d.rect == CGRect(x: 100, y: 500, width: 500, height: 500))
        #expect(d.source == "modelBox")
        #expect(d.notes.isEmpty)
    }

    @Test func modelBoxOverflowIsNotedAndClamped() {
        let d = ClosetImaging.cropRect(
            for: garment(box: GarmentBox(x: 600, y: 600, width: 800, height: 800)),
            strategy: .modelBox, imageSize: size, joints: [:], padding: 0
        )
        #expect(d.notes.contains { $0.contains("overflows") })
        #expect(d.rect.maxX <= size.width && d.rect.maxY <= size.height)
    }

    @Test func tinyModelBoxFallsBack() {
        let d = ClosetImaging.cropRect(
            for: garment(box: GarmentBox(x: 10, y: 10, width: 5, height: 5)),
            strategy: .modelBox, imageSize: size, joints: [:], padding: 0
        )
        #expect(d.source.contains("fallback"))
        #expect(d.rect == CGRect(origin: .zero, size: size))
    }

    @Test func bodyPoseTopSpansShouldersToHips() {
        let joints: [HumanBodyPoseObservation.JointName: CGPoint] = [
            .leftShoulder: CGPoint(x: 400, y: 500), .rightShoulder: CGPoint(x: 600, y: 500),
            .neck: CGPoint(x: 500, y: 460),
            .leftHip: CGPoint(x: 430, y: 1000), .rightHip: CGPoint(x: 570, y: 1000)
        ]
        let d = ClosetImaging.cropRect(for: garment(category: .top), strategy: .bodyPose,
                                       imageSize: size, joints: joints, padding: 0)
        #expect(d.source == "bodyPose(top)")
        #expect(d.rect.minY < 460)          // above the neck
        #expect(d.rect.maxY > 1000)         // below the hips
        #expect(d.rect.maxY < 1200)         // but not down to the knees
        #expect(d.rect.minX < 400 && d.rect.maxX > 600)
    }

    @Test func bodyPoseShoesWithoutAnklesFallsBack() {
        let d = ClosetImaging.cropRect(for: garment(category: .shoes), strategy: .bodyPose,
                                       imageSize: size, joints: [:], padding: 0)
        #expect(d.source.contains("fallback"))
        #expect(d.notes.contains { $0.contains("Required joints missing") })
    }
}

// MARK: - Settings / persistence

@MainActor
struct ClosetSettingsTests {

    @Test func diffListsOnlyChangedKeys() {
        let a = ClosetDebugSettings()
        var b = a
        #expect(settingsDiff(a, b).isEmpty)
        b.matchThreshold = 0.9
        b.backend = .privateCloud
        let diff = settingsDiff(a, b)
        #expect(diff.count == 2)
        #expect(diff.contains { $0.hasPrefix("matchThreshold") })
        #expect(diff.contains { $0.hasPrefix("backend") })
    }

    @Test func closetItemRoundTripsThroughJSON() throws {
        var original = item(from: garment())
        original.wornOn = [UUID()]
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([ClosetItem].self, from: data)
        #expect(decoded == [original])
    }
}
