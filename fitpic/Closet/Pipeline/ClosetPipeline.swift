import UIKit
import FoundationModels
import Vision

// MARK: - ClosetPipeline

/// Runs the closet-cataloging pipeline and records every intermediate into a
/// `PipelineRun` trace:
///
///   0. Environment      – model availability / capabilities / context size
///   1. Normalize        – upright + downscale
///   2. Segment person   – Vision person instance mask, background replaced
///   3. Body pose        – Vision joints (used by the bodyPose crop strategy)
///   4. Detect garments  – Foundation Models, image attachment → OutfitAnalysis
///   5. Crops + prints   – per-item crop + Vision feature print
///   6. Match            – feature distance + attribute penalty vs. closet
///   7. LLM re-rank      – optional: model picks among top-K candidates
///
/// Nothing is written to the closet here; the user commits proposals from the UI.
enum ClosetPipeline {

    /// Creates the run immediately (so UI can observe it) and executes it async.
    static func start(
        image: UIImage,
        fitPicID: UUID?,
        settings: ClosetDebugSettings,
        closet: [ClosetItem]
    ) -> PipelineRun {
        let run = PipelineRun(fitPicID: fitPicID, settings: settings, sourceImage: image)
        Task { await execute(run, closet: closet) }
        return run
    }

    private static func execute(_ run: PipelineRun, closet: [ClosetItem]) async {
        let start = Date()
        defer {
            run.totalDuration = Date().timeIntervalSince(start)
            run.writeExportToDisk()
        }

        environmentStage(run)

        guard let normalized = await normalizeStage(run) else {
            run.status = .failed("Could not normalize image")
            return
        }
        let analysisImage = await segmentationStage(run, image: normalized)
        let joints = await bodyPoseStage(run, image: analysisImage)

        guard let garments = await detectionStage(run, image: analysisImage) else {
            run.status = .failed("Garment detection failed — see stage 4")
            return
        }

        await cropStage(run, image: analysisImage, garments: garments, joints: joints)
        matchStage(run, closet: closet)

        if run.settings.useLLMRerank, run.settings.backend != .mock {
            await rerankStage(run, closet: closet)
        } else {
            run.skipStage("7 · LLM re-rank", reason: run.settings.backend == .mock ? "not available with mock backend" : "disabled in settings")
        }

        run.status = .finished
    }

    // MARK: 0 · Environment

    private static func environmentStage(_ run: PipelineRun) {
        let s = run.beginStage("0 · Environment")
        let settings = run.settings

        let system = SystemLanguageModel(useCase: settings.useContentTaggingUseCase ? .contentTagging : .general)
        run.metric(s, "system.availability", describe(system.availability))
        run.metric(s, "system.vision", "\(system.capabilities.contains(.vision))")
        run.metric(s, "system.guidedGeneration", "\(system.capabilities.contains(.guidedGeneration))")
        run.metric(s, "system.contextSize", "\(system.contextSize)")
        run.metric(s, "system.localeSupported", "\(system.supportsLocale())")

        let pcc = PrivateCloudComputeLanguageModel()
        run.metric(s, "pcc.availability", describe(pcc.availability))
        run.metric(s, "pcc.vision", "\(pcc.capabilities.contains(.vision))")
        run.metric(s, "pcc.reasoning", "\(pcc.capabilities.contains(.reasoning))")
        run.text(s, "pcc.quotaUsage", String(describing: pcc.quotaUsage))

        let src = run.sourceImage
        run.metric(s, "input.points", "\(Int(src.size.width))×\(Int(src.size.height)) @\(Int(src.scale))x")
        run.metric(s, "input.orientation", "\(src.imageOrientation.rawValue)")
        run.metric(s, "backend", settings.backend.rawValue)

        let selectedAvailable: Bool = {
            switch settings.backend {
            case .onDevice:     return system.isAvailable
            case .privateCloud: return pcc.isAvailable
            case .mock:         return true
            }
        }()
        if !selectedAvailable {
            run.log(s, "Selected backend (\(settings.backend.rawValue)) reports unavailable — detection will likely fail.")
        }
        run.endStage(s, selectedAvailable ? .ok : .warning)
    }

    // MARK: 1 · Normalize

    private static func normalizeStage(_ run: PipelineRun) async -> CGImage? {
        let s = run.beginStage("1 · Normalize")
        guard let cg = await ClosetImaging.normalize(run.sourceImage, maxDimension: run.settings.maxImageDimension) else {
            run.log(s, "Rendering failed")
            run.endStage(s, .failed)
            return nil
        }
        run.metric(s, "output.pixels", "\(cg.width)×\(cg.height)")
        run.metric(s, "maxImageDimension", "\(run.settings.maxImageDimension)")
        run.image(s, "normalized", UIImage(cgImage: cg))
        run.endStage(s)
        return cg
    }

    // MARK: 2 · Segmentation

    private static func segmentationStage(_ run: PipelineRun, image: CGImage) async -> CGImage {
        guard run.settings.segmentPerson else {
            run.skipStage("2 · Segment person", reason: "disabled in settings; using normalized image")
            return image
        }
        let s = run.beginStage("2 · Segment person")
        do {
            guard let result = try await ClosetImaging.segmentPerson(image, background: run.settings.background) else {
                run.log(s, "No person instances found; falling back to normalized image")
                run.endStage(s, .warning)
                return image
            }
            run.metric(s, "instances", "\(result.instanceCount)")
            run.metric(s, "confidence", String(format: "%.3f", result.confidence))
            run.metric(s, "output.pixels", "\(result.image.width)×\(result.image.height)")
            run.metric(s, "background", run.settings.background.rawValue)
            if result.instanceCount > 1 {
                run.log(s, "⚠️ \(result.instanceCount) people found — all are kept in the crop; other people's clothes may be detected.")
            }
            if let mask = result.mask { run.image(s, "mask", UIImage(cgImage: mask)) }
            run.image(s, "person (sent to model)", UIImage(cgImage: result.image))
            run.endStage(s, result.instanceCount > 1 ? .warning : .ok)
            return result.image
        } catch {
            run.log(s, "Error: \(error)")
            run.endStage(s, .failed)
            return image
        }
    }

    // MARK: 3 · Body pose

    private static func bodyPoseStage(
        _ run: PipelineRun,
        image: CGImage
    ) async -> [HumanBodyPoseObservation.JointName: CGPoint] {
        let s = run.beginStage("3 · Body pose")
        do {
            let observations = try await ClosetImaging.detectBodyPose(image)
            run.metric(s, "bodies", "\(observations.count)")
            guard let best = observations.max(by: { $0.confidence < $1.confidence }) else {
                run.log(s, "No body detected — bodyPose crops will fall back to full image")
                run.endStage(s, .warning)
                return [:]
            }
            let size = CGSize(width: image.width, height: image.height)
            let joints = ClosetImaging.joints(of: best, imageSize: size, minConfidence: run.settings.minimumJointConfidence)
            run.metric(s, "confidence", String(format: "%.3f", best.confidence))
            run.metric(s, "joints ≥ \(run.settings.minimumJointConfidence)", "\(joints.count)/\(best.availableJointNames.count)")

            let jointDump = best.allJoints()
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { name, joint in
                    let p = joint.location
                    let kept = Double(joint.confidence) >= run.settings.minimumJointConfidence ? "✓" : "✗"
                    return "\(kept) \(name.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)) conf=\(String(format: "%.2f", joint.confidence)) norm=(\(String(format: "%.3f", p.x)), \(String(format: "%.3f", p.y)))"
                }
                .joined(separator: "\n")
            run.text(s, "joints", jointDump)
            run.image(s, "pose overlay", ClosetImaging.overlay(joints: joints, on: image))
            run.endStage(s)
            return joints
        } catch {
            run.log(s, "Error: \(error)")
            run.endStage(s, .failed)
            return [:]
        }
    }

    // MARK: 4 · Detection

    private static func detectionStage(_ run: PipelineRun, image: CGImage) async -> [DetectedGarment]? {
        let s = run.beginStage("4 · Detect garments (\(run.settings.backend.rawValue))")
        let settings = run.settings

        run.text(s, "instructions", settings.instructions)
        run.text(s, "prompt", settings.prompt)
        run.text(s, "schema", String(describing: OutfitAnalysis.generationSchema))
        run.image(s, "attachment", UIImage(cgImage: image))

        // Pre-flight token accounting (on-device model only exposes tokenCount).
        if settings.backend == .onDevice {
            let system = SystemLanguageModel(useCase: settings.useContentTaggingUseCase ? .contentTagging : .general)
            if let imageTokens = try? await system.tokenCount(for: Attachment(image)) {
                run.metric(s, "tokens.image", "\(imageTokens)")
            }
            if let instructionTokens = try? await system.tokenCount(for: Instructions(settings.instructions)) {
                run.metric(s, "tokens.instructions", "\(instructionTokens)")
            }
            if let promptTokens = try? await system.tokenCount(for: settings.prompt) {
                run.metric(s, "tokens.prompt", "\(promptTokens)")
            }
            if let schemaTokens = try? await system.tokenCount(for: OutfitAnalysis.generationSchema) {
                run.metric(s, "tokens.schema", "\(schemaTokens)")
            }
            run.metric(s, "contextSize", "\(system.contextSize)")
        }

        // Fail fast with an actionable message instead of letting the framework
        // surface opaque asset errors (e.g. UnifiedAssetFramework Code=5000).
        if let blocker = preflightBlocker(settings) {
            run.log(s, "Not calling the model: \(blocker)")
            run.endStage(s, .failed)
            return nil
        }

        let options = generationOptions(settings)
        let context = contextOptions(settings)
        run.metric(s, "sampling", settings.greedySampling ? "greedy" : "temperature \(settings.temperature)")
        run.metric(s, "maxResponseTokens", "\(settings.maxResponseTokens)")

        let started = Date()
        do {
            let analysis: OutfitAnalysis
            switch settings.backend {
            case .onDevice:
                let model = SystemLanguageModel(useCase: settings.useContentTaggingUseCase ? .contentTagging : .general)
                let response = try await detect(model: model, image: image, settings: settings, options: options, context: context)
                record(run, stage: s, response)
                analysis = response.content
            case .privateCloud:
                let response = try await detect(model: PrivateCloudComputeLanguageModel(), image: image, settings: settings, options: options, context: context)
                record(run, stage: s, response)
                analysis = response.content
            case .mock:
                run.log(s, "MOCK backend: decoding mockResponseJSON from settings; no model call made.")
                analysis = try JSONDecoder().decode(OutfitAnalysis.self, from: Data(settings.mockResponseJSON.utf8))
                run.text(s, "raw response JSON", settings.mockResponseJSON)
            }
            let latency = Date().timeIntervalSince(started)
            run.metric(s, "latency", String(format: "%.2fs", latency))

            let all = analysis.items
            let kept = all.filter { $0.confidence >= settings.minimumConfidence }
            run.metric(s, "items.returned", "\(all.count)")
            run.metric(s, "items.kept (conf ≥ \(settings.minimumConfidence))", "\(kept.count)")
            for dropped in all where dropped.confidence < settings.minimumConfidence {
                run.log(s, "Dropped low-confidence item: \(dropped.name) (\(dropped.confidence))")
            }

            let boxes = all.map { garment -> (CGRect, String) in
                let b = garment.box
                let rect = CGRect(x: CGFloat(b.x) / 1000 * CGFloat(image.width),
                                  y: CGFloat(b.y) / 1000 * CGFloat(image.height),
                                  width: CGFloat(b.width) / 1000 * CGFloat(image.width),
                                  height: CGFloat(b.height) / 1000 * CGFloat(image.height))
                return (rect, "\(garment.name) \(garment.confidence)")
            }
            run.image(s, "model boxes (raw)", ClosetImaging.overlay(boxes: boxes, on: image))

            run.endStage(s, kept.isEmpty ? .warning : .ok)
            return kept
        } catch {
            run.metric(s, "latency", String(format: "%.2fs", Date().timeIntervalSince(started)))
            run.log(s, "Error: \(error.localizedDescription)")
            run.text(s, "error (debug)", String(reflecting: error))
            run.endStage(s, .failed)
            return nil
        }
    }

    private static func detect<M: LanguageModel>(
        model: M,
        image: CGImage,
        settings: ClosetDebugSettings,
        options: GenerationOptions,
        context: ContextOptions
    ) async throws -> LanguageModelSession.Response<OutfitAnalysis> {
        let session = LanguageModelSession(model: model, instructions: settings.instructions)
        return try await session.respond(
            generating: OutfitAnalysis.self,
            options: options,
            contextOptions: context
        ) {
            settings.prompt
            Attachment(image).label("outfit")
        }
    }

    // MARK: 5 · Crops + feature prints

    private static func cropStage(
        _ run: PipelineRun,
        image: CGImage,
        garments: [DetectedGarment],
        joints: [HumanBodyPoseObservation.JointName: CGPoint]
    ) async {
        let s = run.beginStage("5 · Crops + feature prints")
        let settings = run.settings
        let size = CGSize(width: image.width, height: image.height)
        run.metric(s, "strategy", settings.cropStrategy.rawValue)
        run.metric(s, "padding", String(format: "%.2f", settings.cropPadding))

        var proposals: [ItemProposal] = []
        var hadFallback = false

        for (index, garment) in garments.enumerated() {
            let decision = ClosetImaging.cropRect(
                for: garment,
                strategy: settings.cropStrategy,
                imageSize: size,
                joints: joints,
                padding: settings.cropPadding
            )
            decision.notes.forEach { run.log(s, "[\(index)] \($0)") }
            hadFallback = hadFallback || decision.source.contains("fallback")

            var proposal = ItemProposal(garment: garment)
            proposal.cropRect = decision.rect
            proposal.cropSource = decision.source

            if let cropped = ClosetImaging.crop(image, to: decision.rect) {
                proposal.crop = UIImage(cgImage: cropped)
                let printStart = Date()
                do {
                    proposal.featurePrint = try await ClosetImaging.featurePrint(for: cropped)
                    let ms = Int(Date().timeIntervalSince(printStart) * 1000)
                    run.log(s, "[\(index)] \(garment.name): \(decision.source) rect=\(NSCoder.string(for: decision.rect)) print=\(proposal.featurePrint?.elementCount ?? 0) elems in \(ms)ms")
                } catch {
                    hadFallback = true
                    run.log(s, "[\(index)] feature print failed: \(error)")
                }
                run.image(s, "[\(index)] \(garment.name)", proposal.crop)
            } else {
                run.log(s, "[\(index)] crop failed for rect \(decision.rect)")
            }
            proposals.append(proposal)
        }

        run.image(s, "crop overlay", ClosetImaging.overlay(
            boxes: proposals.compactMap { p in p.cropRect.map { ($0, p.garment.name) } },
            on: image
        ))
        run.proposals = proposals
        run.endStage(s, hadFallback ? .warning : .ok)
    }

    // MARK: 6 · Match

    private static func matchStage(_ run: PipelineRun, closet: [ClosetItem]) {
        let s = run.beginStage("6 · Match against closet")
        let settings = run.settings
        run.metric(s, "closet.size", "\(closet.count)")
        run.metric(s, "threshold", ClosetMatcher.fmt(settings.matchThreshold))
        run.metric(s, "attributeWeight", ClosetMatcher.fmt(settings.attributeWeight))
        run.metric(s, "requireSameCategory", "\(settings.requireSameCategory)")

        var table: [String] = []
        var matched = 0
        for index in run.proposals.indices {
            let garment = run.proposals[index].garment
            let candidates = ClosetMatcher.rank(
                garment: garment,
                featurePrint: run.proposals[index].featurePrint,
                closet: closet,
                settings: settings
            )
            run.proposals[index].candidates = candidates
            let suggestion = candidates.first(where: \.passesThreshold)
            run.proposals[index].suggestedMatchID = suggestion?.itemID
            run.proposals[index].decision = suggestion.map { .match($0.itemID) } ?? .createNew
            if suggestion != nil { matched += 1 }

            table.append("[\(index)] \(garment.name) (\(garment.category.rawValue)) → \(suggestion?.itemName ?? "NEW")")
            if candidates.isEmpty { table.append("     (no eligible candidates)") }
            for (rank, c) in candidates.prefix(5).enumerated() {
                let fd = c.featureDistance.map(ClosetMatcher.fmt) ?? " n/a"
                table.append("     #\(rank + 1) \(c.passesThreshold ? "✅" : "  ") \(c.itemName)  fd=\(fd) attr=\(ClosetMatcher.fmt(c.attributePenalty)) ⇒ \(ClosetMatcher.fmt(c.combinedScore))")
                table.append("          \(c.attributeNotes.joined(separator: " | "))")
            }
        }
        run.metric(s, "matched", "\(matched)/\(run.proposals.count)")
        run.text(s, "score table", table.joined(separator: "\n"))
        run.endStage(s)
    }

    // MARK: 7 · LLM re-rank

    private static func rerankStage(_ run: PipelineRun, closet: [ClosetItem]) async {
        let s = run.beginStage("7 · LLM re-rank (\(run.settings.backend.rawValue))")
        let settings = run.settings
        run.metric(s, "topK", "\(settings.rerankTopK)")
        run.metric(s, "includeImages", "\(settings.rerankIncludeImages)")

        var anyFailure = false
        for index in run.proposals.indices {
            let proposal = run.proposals[index]
            let top = Array(proposal.candidates.prefix(settings.rerankTopK))
            guard !top.isEmpty else {
                run.log(s, "[\(index)] no candidates; skipped")
                continue
            }
            let items = top.compactMap { c in closet.first { $0.id == c.itemID } }
            let detectedImage = settings.rerankIncludeImages ? proposal.crop?.cgImage : nil
            let candidateImages: [CGImage?] = items.map { item in
                guard settings.rerankIncludeImages, let path = item.thumbnailPath else { return nil }
                return ImageStorage.shared.loadThumbnail(path: path, maxPixelSize: 170)?.cgImage
            }

            let promptText = rerankPromptText(garment: proposal.garment, items: items)
            run.text(s, "[\(index)] prompt", promptText)

            let started = Date()
            do {
                let response: LanguageModelSession.Response<MatchDecision>
                switch settings.backend {
                case .onDevice:
                    response = try await rerank(model: SystemLanguageModel.default, garment: proposal.garment, items: items,
                                                detectedImage: detectedImage, candidateImages: candidateImages, settings: settings)
                case .privateCloud:
                    response = try await rerank(model: PrivateCloudComputeLanguageModel(), garment: proposal.garment, items: items,
                                                detectedImage: detectedImage, candidateImages: candidateImages, settings: settings)
                case .mock:
                    continue   // unreachable: the stage is skipped for mock
                }
                let decision = response.content
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                run.text(s, "[\(index)] response", response.rawContent.jsonString)
                run.log(s, "[\(index)] \(proposal.garment.name): matchIndex=\(decision.matchIndex) in \(ms)ms, in=\(response.usage.input.totalTokenCount) out=\(response.usage.output.totalTokenCount) tok")

                run.proposals[index].rerankReason = decision.reason
                if decision.matchIndex >= 0, decision.matchIndex < items.count {
                    let chosen = items[decision.matchIndex]
                    if chosen.id != proposal.suggestedMatchID {
                        run.log(s, "[\(index)] re-rank OVERRIDES heuristic: \(proposal.candidates.first { $0.itemID == proposal.suggestedMatchID }?.itemName ?? "NEW") → \(chosen.name)")
                    }
                    run.proposals[index].suggestedMatchID = chosen.id
                    run.proposals[index].decision = .match(chosen.id)
                } else {
                    if proposal.suggestedMatchID != nil {
                        run.log(s, "[\(index)] re-rank OVERRIDES heuristic → NEW")
                    }
                    run.proposals[index].suggestedMatchID = nil
                    run.proposals[index].decision = .createNew
                }
            } catch {
                anyFailure = true
                run.log(s, "[\(index)] Error: \(error.localizedDescription)")
                run.text(s, "[\(index)] error (debug)", String(reflecting: error))
            }
        }
        run.endStage(s, anyFailure ? .warning : .ok)
    }

    private static func rerankPromptText(garment: DetectedGarment, items: [ClosetItem]) -> String {
        var lines = ["Detected item: \(garment.summary)", "Candidates from the user's closet:"]
        for (i, item) in items.enumerated() { lines.append("[\(i)] \(item.summary)") }
        lines.append("Which candidate is the SAME physical item as the detected item? Similar is not enough. Answer -1 if none.")
        return lines.joined(separator: "\n")
    }

    private static func rerank<M: LanguageModel>(
        model: M,
        garment: DetectedGarment,
        items: [ClosetItem],
        detectedImage: CGImage?,
        candidateImages: [CGImage?],
        settings: ClosetDebugSettings
    ) async throws -> LanguageModelSession.Response<MatchDecision> {
        let session = LanguageModelSession(
            model: model,
            instructions: "You decide whether a clothing item photographed today is one the user already owns."
        )
        return try await session.respond(
            generating: MatchDecision.self,
            options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 300),
            contextOptions: contextOptions(settings)
        ) {
            "Detected item: \(garment.summary)"
            if let detectedImage {
                Attachment(detectedImage).label("detected")
            }
            "Candidates from the user's closet:"
            for (i, item) in items.enumerated() {
                "[\(i)] \(item.summary)"
                if let candidate = candidateImages[i] {
                    Attachment(candidate).label("candidate-\(i)")
                }
            }
            "Which candidate is the SAME physical item as the detected item? Similar is not enough. Answer -1 if none."
        }
    }

    // MARK: Helpers

    private static func generationOptions(_ settings: ClosetDebugSettings) -> GenerationOptions {
        GenerationOptions(
            samplingMode: settings.greedySampling ? .greedy : nil,
            temperature: settings.greedySampling ? nil : settings.temperature,
            maximumResponseTokens: settings.maxResponseTokens
        )
    }

    private static func contextOptions(_ settings: ClosetDebugSettings) -> ContextOptions {
        // Reasoning is only meaningful for Private Cloud Compute; the on-device
        // model may reject it as an unsupported capability.
        let reasoning: ContextOptions.ReasoningLevel? = {
            guard settings.backend == .privateCloud else { return nil }
            switch settings.reasoning {
            case .none:     return nil
            case .light:    return .light
            case .moderate: return .moderate
            case .deep:     return .deep
            }
        }()
        return ContextOptions(includeSchemaInPrompt: settings.includeSchemaInPrompt, reasoningLevel: reasoning)
    }

    private static func record<C>(_ run: PipelineRun, stage: Int, _ response: LanguageModelSession.Response<C>) {
        recordUsage(run, stage: stage, response.usage)
        run.text(stage, "raw response JSON", response.rawContent.jsonString)
        run.text(stage, "transcript", transcriptDump(response.transcriptEntries))
    }

    private static func recordUsage(_ run: PipelineRun, stage: Int, _ usage: LanguageModelSession.Usage) {
        run.metric(stage, "usage.input", "\(usage.input.totalTokenCount) (cached \(usage.input.cachedTokenCount))")
        run.metric(stage, "usage.output", "\(usage.output.totalTokenCount) (reasoning \(usage.output.reasoningTokenCount))")
    }

    private static func transcriptDump(_ entries: ArraySlice<Transcript.Entry>) -> String {
        let text = entries.map { String(describing: $0) }.joined(separator: "\n---\n")
        return text.count > 6000 ? String(text.prefix(6000)) + "\n…(truncated)" : text
    }

    /// Human-readable reason the selected backend can't run, or nil if it can.
    static func preflightBlocker(_ settings: ClosetDebugSettings) -> String? {
        switch settings.backend {
        case .mock:
            return nil
        case .onDevice:
            #if targetEnvironment(simulator)
            return "Image input to Foundation Models isn't supported in the Simulator (MultimodalSanitizer: 'Simulator is not supported'). Run on a device, or use the Mock backend."
            #else
            let model = SystemLanguageModel(useCase: settings.useContentTaggingUseCase ? .contentTagging : .general)
            switch model.availability {
            case .available:
                return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence is off. Enable it in Settings → Apple Intelligence & Siri, then wait for the model download."
            case .unavailable(.modelNotReady):
                return "The on-device model is still downloading or not installed (asset catalog empty). Keep the device on Wi-Fi and power, make sure there's free storage, check Settings → Apple Intelligence & Siri, and retry later."
            case .unavailable(.deviceNotEligible):
                return "This device doesn't support Apple Intelligence. Try Private Cloud Compute or Mock."
            case .unavailable(let other):
                return "On-device model unavailable: \(other)"
            }
            #endif
        case .privateCloud:
            #if targetEnvironment(simulator)
            return "Private Cloud Compute isn't available in the Simulator. Run on a device, or use the Mock backend."
            #else
            switch PrivateCloudComputeLanguageModel().availability {
            case .available:
                return nil
            case .unavailable(let reason):
                return "Private Cloud Compute unavailable (\(reason)). Check the PCC entitlement and that Apple Intelligence is enabled."
            }
            #endif
        }
    }

    private static func describe(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available: return "available"
        case .unavailable(let reason): return "unavailable(\(reason))"
        }
    }

    private static func describe(_ availability: PrivateCloudComputeLanguageModel.Availability) -> String {
        switch availability {
        case .available: return "available"
        case .unavailable(let reason): return "unavailable(\(reason))"
        }
    }
}
