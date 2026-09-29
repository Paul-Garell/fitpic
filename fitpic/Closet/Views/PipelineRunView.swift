import SwiftUI

// MARK: - PipelineRunView

/// Renders a live `PipelineRun`: header, every stage's trace, then the
/// reviewable item proposals with a commit button.
struct PipelineRunView: View {

    @Bindable var run: PipelineRun
    /// Current settings, used to show what changed since this run was made.
    let currentSettings: ClosetDebugSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ForEach(run.stages) { stage in
                StageTraceView(stage: stage, runStart: run.startedAt)
            }

            if run.status == .running {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Running…").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            if run.status == .finished || run.status == .committed {
                ProposalsReviewView(run: run)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusBadge
                Spacer()
                Text(run.startedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(run.headline)
                .font(.subheadline.monospaced())

            let diff = settingsDiff(run.settings, currentSettings)
            if !diff.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings changed since this run:")
                        .font(.caption.bold())
                    ForEach(diff, id: \.self) { line in
                        Text(line).font(.caption2.monospaced())
                    }
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch run.status {
        case .running:
            Label("Running", systemImage: "hourglass").foregroundStyle(.blue)
        case .finished:
            Label("Finished — review below", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        case .committed:
            Label("Committed to closet", systemImage: "tray.and.arrow.down.fill").foregroundStyle(.purple)
        }
    }
}

// MARK: - Settings diff

/// Human-readable list of settings keys that differ between two snapshots.
func settingsDiff(_ a: ClosetDebugSettings, _ b: ClosetDebugSettings) -> [String] {
    guard a != b,
          let da = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any],
          let db = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as? [String: Any]
    else { return [] }

    func short(_ value: Any?) -> String {
        let s = value.map { "\($0)" } ?? "nil"
        return s.count > 40 ? String(s.prefix(40)) + "…" : s
    }
    return Set(da.keys).union(db.keys).sorted().compactMap { key in
        let lhs = short(da[key]), rhs = short(db[key])
        return lhs == rhs ? nil : "\(key): \(lhs) → \(rhs)"
    }
}

// MARK: - StageTraceView

struct StageTraceView: View {

    let stage: StageTrace
    let runStart: Date

    @State private var isExpanded = false
    @State private var inspecting: TraceImage?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if !stage.metrics.isEmpty { metricsGrid }
                if !stage.logs.isEmpty { logList }
                if !stage.images.isEmpty { imageStrip }
                ForEach(stage.texts) { text in
                    TraceTextBlock(text: text)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: stage.status.symbolName)
                    .foregroundStyle(statusColor)
                Text(stage.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let duration = stage.duration {
                    Text("\(Int(duration * 1000)) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        .onAppear {
            // Surface problems immediately.
            if stage.status == .failed || stage.status == .warning { isExpanded = true }
        }
        .onChange(of: stage.status) { _, status in
            if status == .failed || status == .warning { isExpanded = true }
        }
        .sheet(item: $inspecting) { image in
            ImageInspectorView(traceImage: image)
        }
    }

    private var statusColor: Color {
        switch stage.status {
        case .running: return .blue
        case .ok:      return .green
        case .warning: return .orange
        case .failed:  return .red
        case .skipped: return .secondary
        }
    }

    private var metricsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(stage.metrics) { metric in
                GridRow {
                    Text(metric.key)
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .textSelection(.enabled)
                }
                .font(.caption.monospaced())
            }
        }
    }

    private var logList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(stage.logs) { line in
                Text("+\(String(format: "%.3f", line.offset))s  \(line.message)")
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private var imageStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(stage.images) { traceImage in
                    Button { inspecting = traceImage } label: {
                        VStack(spacing: 4) {
                            Image(uiImage: traceImage.image)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 140)
                                .background(checkerboard)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(traceImage.label)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(maxWidth: 120)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Inspect image: \(traceImage.label)")
                }
            }
        }
    }

    /// Grey backing so transparent regions are visible.
    private var checkerboard: some View {
        Color(.systemGray5)
    }
}

// MARK: - TraceTextBlock

private struct TraceTextBlock: View {
    let text: TraceText
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ScrollView(.horizontal) {
                Text(text.content)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(8)
            }
            .frame(maxHeight: 320)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemGroupedBackground)))
        } label: {
            HStack {
                Text(text.label).font(.caption.weight(.medium))
                Text("\(text.content.count) chars").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = text.content
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy \(text.label)")
            }
        }
    }
}

// MARK: - ImageInspectorView

struct ImageInspectorView: View {
    let traceImage: TraceImage
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: traceImage.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width * zoom * pinch)
                        .background(Color(.systemGray5))
                }
            }
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = min(max(zoom * value.magnification, 1), 8) }
            )
            .navigationTitle(traceImage.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    let px = traceImage.image.cgImage.map { "\($0.width)×\($0.height)px" } ?? ""
                    Text(px).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: Image(uiImage: traceImage.image),
                              preview: SharePreview(traceImage.label, image: Image(uiImage: traceImage.image)))
                }
            }
        }
    }
}
