import Foundation
import Observation
import UIKit
import Vision
import os

// MARK: - Trace primitives

nonisolated enum StageStatus: String, Codable, Sendable {
    case running, ok, warning, failed, skipped

    var symbolName: String {
        switch self {
        case .running: return "hourglass"
        case .ok:      return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed:  return "xmark.octagon.fill"
        case .skipped: return "minus.circle"
        }
    }
}

nonisolated struct TraceMetric: Identifiable, Codable, Sendable {
    var id: String { key }
    let key: String
    let value: String
}

nonisolated struct TraceText: Identifiable, Codable, Sendable {
    let id: UUID
    let label: String
    let content: String
}

struct TraceImage: Identifiable {
    let id = UUID()
    let label: String
    let image: UIImage
}

nonisolated struct TraceLogLine: Identifiable, Codable, Sendable {
    let id: UUID
    let offset: TimeInterval   // seconds since run start
    let message: String
}

/// Everything recorded for one pipeline stage.
struct StageTrace: Identifiable {
    let id = UUID()
    let name: String
    var status: StageStatus = .running
    let startedAt: Date
    var duration: TimeInterval?
    var metrics: [TraceMetric] = []
    var logs: [TraceLogLine] = []
    var texts: [TraceText] = []
    var images: [TraceImage] = []
}

// MARK: - Proposals (pipeline output, user-reviewable)

nonisolated struct MatchCandidate: Identifiable, Sendable {
    var id: UUID { itemID }
    let itemID: UUID
    let itemName: String
    /// Minimum Vision feature-print distance across the item's stored prints (nil if none).
    let featureDistance: Double?
    /// 0 (all attributes agree) … 1 (nothing agrees).
    let attributePenalty: Double
    let combinedScore: Double
    let passesThreshold: Bool
    let attributeNotes: [String]
}

enum ProposalDecision: Hashable {
    case createNew
    case match(UUID)
    case discard
}

struct ItemProposal: Identifiable {
    let id = UUID()
    var garment: DetectedGarment
    var crop: UIImage?
    /// Crop rect in analysis-image pixel coordinates (top-left origin).
    var cropRect: CGRect?
    var cropSource: String = ""
    var featurePrint: FeaturePrintObservation?
    var candidates: [MatchCandidate] = []
    var suggestedMatchID: UUID?
    var rerankReason: String?
    var decision: ProposalDecision = .createNew
}

// MARK: - PipelineRun

/// Live, observable record of one pipeline execution. The debug UI binds to it
/// directly, so stages appear as they run.
@Observable
final class PipelineRun: Identifiable {

    enum Status: Equatable {
        case running
        case finished
        case failed(String)
        case committed
    }

    let id = UUID()
    let startedAt = Date()
    let fitPicID: UUID?
    let settings: ClosetDebugSettings
    let sourceImage: UIImage

    var status: Status = .running
    var stages: [StageTrace] = []
    var proposals: [ItemProposal] = []
    var totalDuration: TimeInterval?

    @ObservationIgnored
    private let logger = Logger(subsystem: "fitpic", category: "ClosetPipeline")

    init(fitPicID: UUID?, settings: ClosetDebugSettings, sourceImage: UIImage) {
        self.fitPicID = fitPicID
        self.settings = settings
        self.sourceImage = sourceImage
    }

    // MARK: Recording API

    @discardableResult
    func beginStage(_ name: String) -> Int {
        stages.append(StageTrace(name: name, startedAt: Date()))
        logger.debug("▶︎ \(name, privacy: .public)")
        return stages.count - 1
    }

    func log(_ stage: Int, _ message: String) {
        stages[stage].logs.append(
            TraceLogLine(id: UUID(), offset: Date().timeIntervalSince(startedAt), message: message)
        )
        logger.debug("[\(self.stages[stage].name, privacy: .public)] \(message, privacy: .public)")
    }

    func metric(_ stage: Int, _ key: String, _ value: String) {
        if let existing = stages[stage].metrics.firstIndex(where: { $0.key == key }) {
            stages[stage].metrics[existing] = TraceMetric(key: key, value: value)
        } else {
            stages[stage].metrics.append(TraceMetric(key: key, value: value))
        }
    }

    func text(_ stage: Int, _ label: String, _ content: String) {
        stages[stage].texts.append(TraceText(id: UUID(), label: label, content: content))
    }

    func image(_ stage: Int, _ label: String, _ image: UIImage?) {
        guard let image else { return }
        stages[stage].images.append(TraceImage(label: label, image: image))
    }

    func endStage(_ stage: Int, _ status: StageStatus = .ok) {
        stages[stage].status = status
        stages[stage].duration = Date().timeIntervalSince(stages[stage].startedAt)
        let ms = Int((stages[stage].duration ?? 0) * 1000)
        logger.debug("■ \(self.stages[stage].name, privacy: .public) \(status.rawValue, privacy: .public) \(ms)ms")
    }

    /// Marks a stage as skipped without running it.
    func skipStage(_ name: String, reason: String) {
        let index = beginStage(name)
        log(index, "Skipped: \(reason)")
        endStage(index, .skipped)
    }

    // MARK: Summary

    var headline: String {
        let items = proposals.count
        let secs = totalDuration.map { String(format: "%.2fs", $0) } ?? "…"
        return "\(settings.backend.rawValue) · \(items) item\(items == 1 ? "" : "s") · \(secs)"
    }
}

// MARK: - Export

/// Image-free, Codable snapshot of a run for sharing / diffing between runs.
nonisolated struct PipelineRunExport: Codable, Sendable {
    struct Stage: Codable, Sendable {
        let name: String
        let status: StageStatus
        let durationMs: Int?
        let metrics: [TraceMetric]
        let logs: [TraceLogLine]
        let texts: [TraceText]
        let imageLabels: [String]
    }
    struct Proposal: Codable, Sendable {
        let garment: DetectedGarment
        let cropSource: String
        let cropRect: String?
        let hasFeaturePrint: Bool
        let candidates: [Candidate]
        let suggestedMatch: String?
        let rerankReason: String?
    }
    struct Candidate: Codable, Sendable {
        let itemName: String
        let featureDistance: Double?
        let attributePenalty: Double
        let combinedScore: Double
        let passesThreshold: Bool
        let attributeNotes: [String]
    }

    let runID: UUID
    let startedAt: Date
    let totalDurationMs: Int?
    let fitPicID: UUID?
    let settings: ClosetDebugSettings
    let stages: [Stage]
    let proposals: [Proposal]
}

extension PipelineRun {

    var export: PipelineRunExport {
        PipelineRunExport(
            runID: id,
            startedAt: startedAt,
            totalDurationMs: totalDuration.map { Int($0 * 1000) },
            fitPicID: fitPicID,
            settings: settings,
            stages: stages.map { stage in
                .init(
                    name: stage.name,
                    status: stage.status,
                    durationMs: stage.duration.map { Int($0 * 1000) },
                    metrics: stage.metrics,
                    logs: stage.logs,
                    texts: stage.texts,
                    imageLabels: stage.images.map(\.label)
                )
            },
            proposals: proposals.map { proposal in
                .init(
                    garment: proposal.garment,
                    cropSource: proposal.cropSource,
                    cropRect: proposal.cropRect.map { NSCoder.string(for: $0) },
                    hasFeaturePrint: proposal.featurePrint != nil,
                    candidates: proposal.candidates.map {
                        .init(itemName: $0.itemName,
                              featureDistance: $0.featureDistance,
                              attributePenalty: $0.attributePenalty,
                              combinedScore: $0.combinedScore,
                              passesThreshold: $0.passesThreshold,
                              attributeNotes: $0.attributeNotes)
                    },
                    suggestedMatch: proposal.suggestedMatchID.flatMap { id in
                        proposal.candidates.first { $0.itemID == id }?.itemName
                    },
                    rerankReason: proposal.rerankReason
                )
            }
        )
    }

    var exportJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    /// Writes the export JSON to Documents/ClosetDebug/ and returns the URL.
    @discardableResult
    func writeExportToDisk() -> URL? {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClosetDebug", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let url = dir.appendingPathComponent("run-\(formatter.string(from: startedAt)).json")
            try exportJSON.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
