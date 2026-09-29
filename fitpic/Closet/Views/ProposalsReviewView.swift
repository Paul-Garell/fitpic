import SwiftUI

// MARK: - ProposalsReviewView

/// The "best guess, user confirms" step: one row per detected item with its
/// crop, attributes, ranked candidates and a decision picker.
struct ProposalsReviewView: View {

    @Bindable var run: PipelineRun
    @EnvironmentObject private var closet: ClosetStore
    @State private var commitResult: ClosetStore.CommitResult?

    private var isCommitted: Bool { run.status == .committed }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proposals (\(run.proposals.count))")
                .font(.headline)

            if run.proposals.isEmpty {
                Text("No items detected. Check stage 4's raw response and the image that was attached.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach($run.proposals) { $proposal in
                ProposalRow(proposal: $proposal, index: run.proposals.firstIndex { $0.id == proposal.id } ?? 0)
                    .disabled(isCommitted)
            }

            if !run.proposals.isEmpty {
                Button {
                    commitResult = closet.commit(run)
                } label: {
                    Label(isCommitted ? "Committed" : "Commit to closet", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCommitted)

                if run.fitPicID == nil {
                    Text("Source is a library photo, so items won't be linked to a fit pic.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Committed", isPresented: Binding(
            get: { commitResult != nil },
            set: { if !$0 { commitResult = nil } }
        )) {
            Button("OK") { commitResult = nil }
        } message: {
            if let r = commitResult {
                Text("\(r.created) new · \(r.matched) matched · \(r.discarded) discarded")
            }
        }
    }
}

// MARK: - ProposalRow

private struct ProposalRow: View {

    @Binding var proposal: ItemProposal
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                cropThumbnail
                attributes
            }
            candidatesList
            if let reason = proposal.rerankReason {
                Label(reason, systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }
            decisionPicker
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(alignment: .topLeading) {
            Text("\(index)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(4)
                .background(Circle().fill(Color(ClosetImaging.palette[index % ClosetImaging.palette.count])))
                .offset(x: -4, y: -4)
        }
    }

    @ViewBuilder
    private var cropThumbnail: some View {
        if let crop = proposal.crop {
            Image(uiImage: crop)
                .resizable()
                .scaledToFit()
                .frame(width: 90, height: 110)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Crop of \(proposal.garment.name)")
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .frame(width: 90, height: 110)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }

    private var attributes: some View {
        let g = proposal.garment
        return VStack(alignment: .leading, spacing: 3) {
            Label(g.name, systemImage: g.category.symbolName)
                .font(.subheadline.bold())
            Text("\(g.category.rawValue) · \(g.primaryColor)\(g.secondaryColor.lowercased() == "none" ? "" : " / \(g.secondaryColor)")")
            Text("\(g.pattern.rawValue) · \(g.material)")
            if !g.details.isEmpty {
                Text(g.details).foregroundStyle(.secondary)
            }
            Text("conf \(g.confidence) · \(proposal.cropSource) · print \(proposal.featurePrint == nil ? "✗" : "✓")")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    @ViewBuilder
    private var candidatesList: some View {
        if proposal.candidates.isEmpty {
            Text("No candidates in closet for this category.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(proposal.candidates.prefix(3)) { c in
                    HStack(spacing: 6) {
                        Image(systemName: c.passesThreshold ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(c.passesThreshold ? .green : .secondary)
                        Text(c.itemName).lineLimit(1)
                        Spacer()
                        Text("fd \(c.featureDistance.map(ClosetMatcher.fmt) ?? "n/a") · attr \(ClosetMatcher.fmt(c.attributePenalty)) ⇒ \(ClosetMatcher.fmt(c.combinedScore))")
                            .monospacedDigit()
                    }
                    .font(.caption2.monospaced())
                }
            }
        }
    }

    private var decisionPicker: some View {
        Picker("Decision", selection: $proposal.decision) {
            Text("➕ New item").tag(ProposalDecision.createNew)
            ForEach(proposal.candidates.prefix(5)) { c in
                Text("🔗 \(c.itemName) (\(ClosetMatcher.fmt(c.combinedScore)))")
                    .tag(ProposalDecision.match(c.itemID))
            }
            Text("🗑 Discard").tag(ProposalDecision.discard)
        }
        .pickerStyle(.menu)
    }
}
