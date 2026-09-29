import SwiftUI

// MARK: - ClosetDebugSettingsView

/// Every pipeline knob in one form. Changes persist immediately and apply
/// to the next run (each run keeps its own snapshot).
struct ClosetDebugSettingsView: View {

    @EnvironmentObject private var store: ClosetDebugSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                normalizeSection
                segmentationSection
                detectionSection
                promptSection
                cropSection
                matchingSection
                rerankSection

                Section {
                    Button("Reset all to defaults", role: .destructive) { store.resetToDefaults() }
                }
            }
            .navigationTitle("Pipeline Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Sections

    private var normalizeSection: some View {
        Section {
            Stepper(value: $store.settings.maxImageDimension, in: 256...2048, step: 128) {
                LabeledContent("Max image edge", value: "\(store.settings.maxImageDimension) px")
            }
        } header: {
            Text("1 · Normalize")
        } footer: {
            Text("Bigger images cost more tokens and latency. Check stage 4's tokens.image metric.")
        }
    }

    private var segmentationSection: some View {
        Section("2 · Segment person") {
            Toggle("Segment person", isOn: $store.settings.segmentPerson)
            Picker("Background", selection: $store.settings.background) {
                ForEach(PreprocessBackground.allCases) { Text($0.rawValue).tag($0) }
            }
            .disabled(!store.settings.segmentPerson)
        }
    }

    private var detectionSection: some View {
        Section {
            Picker("Backend", selection: $store.settings.backend) {
                ForEach(DetectionBackend.allCases) { Text($0.label).tag($0) }
            }
            Toggle("contentTagging use case", isOn: $store.settings.useContentTaggingUseCase)
                .disabled(store.settings.backend != .onDevice)
            Toggle("Greedy sampling", isOn: $store.settings.greedySampling)
            if !store.settings.greedySampling {
                SliderRow(label: "Temperature", value: $store.settings.temperature, range: 0...2, step: 0.05)
            }
            Stepper(value: $store.settings.maxResponseTokens, in: 200...4000, step: 100) {
                LabeledContent("Max response tokens", value: "\(store.settings.maxResponseTokens)")
            }
            Toggle("Include schema in prompt", isOn: $store.settings.includeSchemaInPrompt)
            Picker("Reasoning (PCC only)", selection: $store.settings.reasoning) {
                ForEach(ReasoningChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .disabled(store.settings.backend != .privateCloud)
            Stepper(value: $store.settings.minimumConfidence, in: 0...100, step: 5) {
                LabeledContent("Min item confidence", value: "\(store.settings.minimumConfidence)")
            }
            if store.settings.backend == .mock {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Mock response JSON").font(.caption.bold())
                        Spacer()
                        Button("Paste") {
                            if let s = UIPasteboard.general.string { store.settings.mockResponseJSON = s }
                        }
                        .font(.caption)
                        Button("Reset") { store.settings.mockResponseJSON = ClosetDebugSettings.defaultMockResponseJSON }
                            .font(.caption)
                    }
                    TextEditor(text: $store.settings.mockResponseJSON)
                        .font(.caption2.monospaced())
                        .frame(minHeight: 140)
                }
            }
        } header: {
            Text("4 · Detect garments")
        } footer: {
            Text("Private Cloud Compute requires its entitlement; without it, stage 0 shows it as unavailable. Mock replays JSON (e.g. copied from a device run's raw response) so you can tune crops and matching anywhere.")
        }
    }

    private var promptSection: some View {
        Section("4 · Instructions & prompt") {
            VStack(alignment: .leading) {
                HStack {
                    Text("Instructions").font(.caption.bold())
                    Spacer()
                    Button("Reset") { store.settings.instructions = ClosetDebugSettings.defaultInstructions }
                        .font(.caption)
                }
                TextEditor(text: $store.settings.instructions)
                    .font(.caption.monospaced())
                    .frame(minHeight: 110)
            }
            VStack(alignment: .leading) {
                HStack {
                    Text("Prompt").font(.caption.bold())
                    Spacer()
                    Button("Reset") { store.settings.prompt = ClosetDebugSettings.defaultPrompt }
                        .font(.caption)
                }
                TextEditor(text: $store.settings.prompt)
                    .font(.caption.monospaced())
                    .frame(minHeight: 90)
            }
        }
    }

    private var cropSection: some View {
        Section {
            Picker("Crop strategy", selection: $store.settings.cropStrategy) {
                ForEach(CropStrategy.allCases) { Text($0.rawValue).tag($0) }
            }
            SliderRow(label: "Padding", value: $store.settings.cropPadding, range: 0...0.3, step: 0.01)
            SliderRow(label: "Min joint confidence", value: $store.settings.minimumJointConfidence, range: 0...1, step: 0.05)
        } header: {
            Text("5 · Crops + feature prints")
        } footer: {
            Text("modelBox uses the LLM's box (often imprecise on small models). bodyPose derives regions from Vision joints by category. Crops feed the feature prints used for matching.")
        }
    }

    private var matchingSection: some View {
        Section {
            Toggle("Require same category", isOn: $store.settings.requireSameCategory)
            SliderRow(label: "Attribute weight", value: $store.settings.attributeWeight, range: 0...1, step: 0.05)
            SliderRow(label: "Match threshold", value: $store.settings.matchThreshold, range: 0...1.5, step: 0.01)
        } header: {
            Text("6 · Match")
        } footer: {
            Text("combined = (1−w)·featureDistance + w·attributePenalty. Match if combined ≤ threshold. Use an item's detail screen to see distances between items you know are different.")
        }
    }

    private var rerankSection: some View {
        Section("7 · LLM re-rank") {
            Toggle("Enable re-rank", isOn: $store.settings.useLLMRerank)
            Stepper(value: $store.settings.rerankTopK, in: 1...5) {
                LabeledContent("Top K candidates", value: "\(store.settings.rerankTopK)")
            }
            .disabled(!store.settings.useLLMRerank)
            Toggle("Attach images", isOn: $store.settings.rerankIncludeImages)
                .disabled(!store.settings.useLLMRerank)
        }
    }
}

// MARK: - SliderRow

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent(label, value: String(format: "%.2f", value))
            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(label)
                .accessibilityValue(String(format: "%.2f", value))
        }
    }
}
