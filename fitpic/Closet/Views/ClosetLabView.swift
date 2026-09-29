import SwiftUI
import PhotosUI

// MARK: - ClosetLabView

/// Debug workbench for the cataloging pipeline: pick a source image, run,
/// inspect every stage, tweak settings, re-run, compare, then commit.
struct ClosetLabView: View {

    @EnvironmentObject private var fitPicStore: FitPicStore
    @EnvironmentObject private var closet: ClosetStore
    @EnvironmentObject private var settingsStore: ClosetDebugSettingsStore
    @Environment(\.dismiss) private var dismiss

    /// Pre-selected fit pic when opened from a feed cell.
    var initialFitPic: FitPic? = nil

    @State private var selectedFitPicID: UUID?
    @State private var libraryImage: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var runs: [PipelineRun] = []          // newest first
    @State private var selectedRunID: UUID?
    @State private var showSettings = false

    private var selectedRun: PipelineRun? {
        runs.first { $0.id == selectedRunID } ?? runs.first
    }

    private var isRunning: Bool { runs.first?.status == .running }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sourceSection
                    settingsSummary
                    if let blocker = ClosetPipeline.preflightBlocker(settingsStore.settings) {
                        Label(blocker, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
                    }
                    runButton
                    if !runs.isEmpty { runPicker }
                    if let run = selectedRun {
                        PipelineRunView(run: run, currentSettings: settingsStore.settings)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Closet Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let run = selectedRun {
                        ShareLink(item: run.exportJSON, preview: SharePreview("Pipeline trace"))
                            .accessibilityLabel("Export trace JSON")
                    }
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Pipeline settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                ClosetDebugSettingsView()
            }
            .onAppear {
                if selectedFitPicID == nil, libraryImage == nil {
                    selectedFitPicID = initialFitPic?.id ?? fitPicStore.allSorted.first?.id
                }
            }
            .task(id: selectedFitPicID) { await loadSelectedFitPic() }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadLibraryPhoto(item) }
            }
        }
    }

    // MARK: Source

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Source").font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                            Text("Library").font(.caption2)
                        }
                        .frame(width: 64, height: 80)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(libraryImage != nil && selectedFitPicID == nil ? Color.accentColor : .clear, lineWidth: 3))
                    }
                    .accessibilityLabel("Choose photo from library")

                    ForEach(fitPicStore.allSorted.prefix(40)) { pic in
                        Button {
                            libraryImage = nil
                            selectedFitPicID = pic.id
                        } label: {
                            AsyncStoredImage(path: pic.imagePath, targetWidth: 64)
                                .frame(width: 64, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedFitPicID == pic.id ? Color.accentColor : .clear, lineWidth: 3))
                                .overlay(alignment: .bottomTrailing) {
                                    let count = closet.items(wornIn: pic.id).count
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.caption2.bold())
                                            .padding(3)
                                            .background(Capsule().fill(.purple))
                                            .foregroundStyle(.white)
                                            .padding(3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Fit pic from \(pic.date.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            }

            if let sourceImage {
                HStack(alignment: .top, spacing: 12) {
                    Image(uiImage: sourceImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedFitPicID != nil ? "Fit pic" : "Library photo").font(.caption.bold())
                        Text("\(Int(sourceImage.size.width * sourceImage.scale))×\(Int(sourceImage.size.height * sourceImage.scale)) px")
                            .font(.caption.monospaced())
                        if let id = selectedFitPicID {
                            let linked = closet.items(wornIn: id)
                            if !linked.isEmpty {
                                Text("Already linked:").font(.caption.bold()).padding(.top, 4)
                                ForEach(linked) { Text("• \($0.name)").font(.caption) }
                            }
                        }
                    }
                }
            } else {
                Text("Pick a fit pic or a library photo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Settings summary

    private var settingsSummary: some View {
        let s = settingsStore.settings
        return Button { showSettings = true } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Settings").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                Group {
                    Text("backend: \(s.backend.rawValue)\(s.backend == .onDevice && s.useContentTaggingUseCase ? " (contentTagging)" : "")")
                    Text("image: \(s.maxImageDimension)px · segment: \(s.segmentPerson ? s.background.rawValue : "off")")
                    Text("sampling: \(s.greedySampling ? "greedy" : "t=\(String(format: "%.2f", s.temperature))") · minConf: \(s.minimumConfidence)")
                    Text("crop: \(s.cropStrategy.rawValue) pad \(String(format: "%.2f", s.cropPadding))")
                    Text("match: thr \(String(format: "%.2f", s.matchThreshold)) · w \(String(format: "%.2f", s.attributeWeight)) · rerank \(s.useLLMRerank ? "top\(s.rerankTopK)" : "off")")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Run

    private var runButton: some View {
        Button {
            guard let sourceImage else { return }
            let run = ClosetPipeline.start(
                image: sourceImage,
                fitPicID: selectedFitPicID,
                settings: settingsStore.settings,
                closet: closet.items
            )
            runs.insert(run, at: 0)
            selectedRunID = run.id
        } label: {
            Label(isRunning ? "Running…" : "Run pipeline", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(sourceImage == nil || isRunning)
    }

    private var runPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Runs this session (\(runs.count))").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                        Button { selectedRunID = run.id } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("#\(runs.count - index)").font(.caption.bold())
                                Text(run.headline).font(.caption2.monospaced())
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(run.id == selectedRun?.id ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Loading

    private func loadSelectedFitPic() async {
        guard let id = selectedFitPicID,
              let pic = fitPicStore.fitPics.first(where: { $0.id == id }) else { return }
        let path = pic.imagePath
        // Same off-main pattern as DailyFeedView / AsyncStoredImage.
        let image: UIImage? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: ImageStorage.shared.load(path: path))
            }
        }
        // Ignore if the selection changed while loading.
        if selectedFitPicID == id { sourceImage = image }
    }

    private func loadLibraryPhoto(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        selectedFitPicID = nil
        libraryImage = image
        sourceImage = image
    }
}
