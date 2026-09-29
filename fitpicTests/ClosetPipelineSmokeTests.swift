import Testing
import UIKit
import FoundationModels
@testable import fitpic

/// Runs the real pipeline (Vision + Foundation Models) on a synthetic image.
/// It doesn't assert detection quality (no person in the image); it verifies
/// every stage executes, records timing, and the run reaches a terminal state
/// rather than hanging or crashing — whatever the model's availability.
@MainActor
struct ClosetPipelineSmokeTests {

    private func syntheticImage() -> UIImage {
        let size = CGSize(width: 800, height: 1000)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.systemRed.setFill()
            ctx.fill(CGRect(x: 250, y: 200, width: 300, height: 350))   // "shirt"
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 280, y: 550, width: 240, height: 400))   // "pants"
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func pipelineReachesTerminalState() async throws {
        let run = ClosetPipeline.start(
            image: syntheticImage(),
            fitPicID: nil,
            settings: ClosetDebugSettings(),
            closet: []
        )

        while run.status == .running {
            try await Task.sleep(for: .milliseconds(200))
        }

        // Print the trace so `xcodebuild test` output shows real environment values.
        for stage in run.stages {
            print("STAGE \(stage.name) → \(stage.status.rawValue) \(Int((stage.duration ?? 0) * 1000))ms")
            for m in stage.metrics { print("   \(m.key) = \(m.value)") }
            for l in stage.logs { print("   log: \(l.message)") }
        }
        print("RUN STATUS: \(run.status)")

        #expect(run.stages.first?.name == "0 · Environment")
        #expect(run.stages.allSatisfy { $0.status != .running && $0.duration != nil })
        #expect(run.stages.contains { $0.name.hasPrefix("4 · Detect") })
        #expect(run.totalDuration != nil)
        #expect(run.exportJSON.contains("\"stages\""))
    }

    /// Mock backend exercises everything downstream of the model: crops,
    /// feature prints, matching and proposal defaults.
    @Test(.timeLimit(.minutes(2)))
    func mockBackendProducesProposalsAndMatches() async throws {
        var settings = ClosetDebugSettings()
        settings.backend = .mock
        settings.cropStrategy = .modelBox
        settings.matchThreshold = 0.2

        // One existing item that agrees on every attribute with the mock sweater.
        let mock = try JSONDecoder().decode(OutfitAnalysis.self, from: Data(settings.mockResponseJSON.utf8))
        let existing = ClosetItem(from: mock.items[0], thumbnailPath: nil, featurePrint: nil)

        let run = ClosetPipeline.start(image: syntheticImage(), fitPicID: nil, settings: settings, closet: [existing])
        while run.status == .running {
            try await Task.sleep(for: .milliseconds(100))
        }
        for stage in run.stages {
            print("MOCK STAGE \(stage.name) → \(stage.status.rawValue)")
            for l in stage.logs { print("   log: \(l.message)") }
        }

        #expect(run.status == .finished)
        #expect(run.proposals.count == 3)
        #expect(run.proposals.allSatisfy { $0.crop != nil && $0.cropSource == "modelBox" })

        let sweater = try #require(run.proposals.first)
        #expect(sweater.suggestedMatchID == existing.id)
        #expect(sweater.decision == .match(existing.id))
        // Jeans / sneakers have no same-category candidates → new items.
        #expect(run.proposals.dropFirst().allSatisfy { $0.decision == .createNew && $0.candidates.isEmpty })
    }

    @Test func settingsDecodeToleratesMissingKeys() throws {
        let partial = #"{"matchThreshold": 0.9, "backend": "mock"}"#
        let decoded = try JSONDecoder().decode(ClosetDebugSettings.self, from: Data(partial.utf8))
        #expect(decoded.matchThreshold == 0.9)
        #expect(decoded.backend == .mock)
        #expect(decoded.cropStrategy == ClosetDebugSettings().cropStrategy)
        #expect(decoded.instructions == ClosetDebugSettings.defaultInstructions)
    }
}
