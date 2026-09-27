import SwiftUI

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject private var store: FitPicStore

    private var stats: FitPicStats { store.stats }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    ProfileHeaderView(memberSince: stats.firstDate)
                    ProfileStatsView(stats: stats)

                    if !stats.topTags.isEmpty {
                        TopTagsView(topTags: stats.topTags)
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
        .tagFilterable()
    }
}

// MARK: - ProfileHeaderView

struct ProfileHeaderView: View {
    let memberSince: Date?

    private var memberSinceText: String {
        guard let memberSince else { return "No fits yet" }
        return "Fitting since \(memberSince.formatted(.dateTime.month(.wide).year()))"
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "person.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                Text("Your Profile")
                    .font(.title)
                    .fontWeight(.bold)

                Text(memberSinceText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(cardBackground)
    }
}

// MARK: - ProfileStatsView

struct ProfileStatsView: View {
    let stats: FitPicStats

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stats")
                .font(.title2)
                .fontWeight(.bold)

            LazyVGrid(columns: columns, spacing: 12) {
                StatCard(title: "Photos", value: "\(stats.totalPhotos)",
                         systemImage: "photo.stack", color: .blue)
                StatCard(title: "Days Tracked", value: "\(stats.daysTracked)",
                         systemImage: "calendar", color: .green)
                StatCard(title: "Current Streak", value: streakText(stats.currentStreak),
                         systemImage: "flame.fill", color: .orange)
                StatCard(title: "Best Streak", value: streakText(stats.longestStreak),
                         systemImage: "trophy.fill", color: .purple)
            }

            if stats.daysTracked > 0 {
                Text("Averaging \(stats.averagePerActiveDay, specifier: "%.1f") fits per active day")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground)
    }

    private func streakText(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }
}

// MARK: - StatCard

struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        )
    }
}

// MARK: - TopTagsView

struct TopTagsView: View {
    let topTags: [(tag: String, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Tags")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 10) {
                ForEach(topTags, id: \.tag) { entry in
                    HStack {
                        TagChip(label: entry.tag)
                        Spacer()
                        Text("\(entry.count)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground)
    }
}

// MARK: - Shared card background

private var cardBackground: some View {
    RoundedRectangle(cornerRadius: 16)
        .fill(Color(.systemBackground))
        .shadow(color: .primary.opacity(0.1), radius: 2, x: 0, y: 1)
}

// MARK: - Preview

#Preview {
    ProfileView()
        .environmentObject(FitPicStore())
}
