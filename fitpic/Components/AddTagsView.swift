import SwiftUI

// MARK: - AddTagsView

/// Tag-entry screen shown after a photo is accepted.
/// Calls `onSubmit` when the user taps Save or Skip.
/// The presenter is responsible for dismissing this sheet — this view never calls dismiss() itself.
struct AddTagsView: View {

    @Binding var tags: [String]
    var onSubmit: () -> Void

    @State private var inputText = ""

    private let suggestions = [
        "Casual", "Formal", "Workout", "Office",
        "Weekend", "Smart Casual", "Athleisure", "Going Out"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !tags.isEmpty {
                        tagSection(title: "Your tags") {
                            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    TagChip(label: tag, isRemovable: true) {
                                        tags.removeAll { $0 == tag }
                                    }
                                }
                            }
                        }
                    }

                    tagSection(title: "Add a tag") {
                        HStack(spacing: 10) {
                            TextField("e.g. Vintage", text: $inputText)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .onSubmit { commitInput() }

                            Button(action: commitInput) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.blue)
                            }
                            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    let available = suggestions.filter { !tags.contains($0) }
                    if !available.isEmpty {
                        tagSection(title: "Suggestions") {
                            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                                ForEach(available, id: \.self) { tag in
                                    Button { tags.append(tag) } label: {
                                        TagChip(label: tag)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Tag your fit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skip", action: onSubmit)
                }
            }
            .safeAreaInset(edge: .bottom) {
                submitButton
            }
        }
    }

    // MARK: Sub-views

    @ViewBuilder
    private func tagSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var submitButton: some View {
        Button(action: onSubmit) {
            Text("Save Fit Pic")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: Actions

    private func commitInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else {
            inputText = ""
            return
        }
        tags.append(trimmed)
        inputText = ""
    }
}
