import SwiftUI

// MARK: - FitPicCell

/// Displays a single FitPic — header date, full-width photo, and a horizontal tag strip.
/// The three-dot menu in the top-right corner surfaces delete and edit-tags actions.
///
/// - Parameter photoAspectRatio: Width-to-height ratio of the photo frame.
///   Defaults to `FitPicCell.defaultAspectRatio` (4:5 portrait).
///   Pass a different value to change shape without touching layout logic.
struct FitPicCell: View {

    /// Default photo aspect ratio: 4 wide : 5 tall — good for full-outfit shots.
    static let defaultAspectRatio: CGFloat = 4.0 / 5.0

    let fitPic: FitPic
    var photoAspectRatio: CGFloat = defaultAspectRatio
    var onDelete: (() -> Void)? = nil
    var onEditTags: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateHeader
            photoStack
            if !fitPic.tags.isEmpty {
                tagStrip
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }

    // MARK: Sub-views

    private var dateHeader: some View {
        Text(fitPic.date.fitPicLabel)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
    }

    private var photoStack: some View {
        ZStack(alignment: .topTrailing) {
            photo
            menuButton
        }
    }

    @ViewBuilder
    private var photo: some View {
        GeometryReader { geo in
            let height = geo.size.width / photoAspectRatio
            Group {
                if let image = ImageStorage.shared.load(path: fitPic.imagePath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemFill))
                        .frame(width: geo.size.width, height: height)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                        }
                }
            }
        }
        // Fix the frame so the parent VStack knows the height
        .aspectRatio(photoAspectRatio, contentMode: .fit)
    }

    private var menuButton: some View {
        Menu {
            if let onEditTags {
                Button {
                    onEditTags()
                } label: {
                    Label("Edit Tags", systemImage: "tag")
                }
            }

            if let onDelete {
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .padding(12)
    }

    private var tagStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(fitPic.tags, id: \.self) { tag in
                    TagChip(label: tag)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - Date formatting helper

private extension Date {
    /// "your fit on September 21st, 2026"
    var fitPicLabel: String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: self)
        let suffix = ordinalSuffix(for: day)

        let monthYear = formatted(.dateTime.month(.wide).year())
        return "your fit on \(monthYear.split(separator: " ").first ?? "") \(day)\(suffix), \(calendar.component(.year, from: self))"
    }

    private func ordinalSuffix(for day: Int) -> String {
        switch day {
        case 11, 12, 13: return "th"
        default:
            switch day % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }
}
