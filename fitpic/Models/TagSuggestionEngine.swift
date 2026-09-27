import Foundation

// MARK: - TagSuggestionEngine

/// Ranks tag suggestions from a user's history, preferring tags that are both
/// frequently and recently used, then fills remaining slots from a static seed list.
///
/// Scoring: each past use of a tag contributes a recency-decayed weight
///   weight = 0.5 ^ (ageInDays / halfLifeDays)
/// so a use today counts ~1.0, a use one half-life ago counts ~0.5, etc.
/// A tag's score is the sum of its uses' weights — rewarding both frequency
/// (more uses) and recency (recent uses weigh more).
enum TagSuggestionEngine {

    /// Default seed tags for users without enough history to fill the list.
    static let seedTags = [
        "Casual", "Formal", "Workout", "Office", "Weekend",
        "Smart Casual", "Athleisure", "Going Out", "Streetwear", "Cozy",
        "Date Night", "Travel", "Layered", "Monochrome", "Vintage"
    ]

    /// How quickly a use's weight halves, in days.
    static let halfLifeDays: Double = 30

    /// Returns up to `limit` suggested tags.
    ///
    /// - Parameters:
    ///   - fitPics: The user's full history.
    ///   - excluding: Tags already chosen for the current post (never suggested).
    ///   - referenceDate: "Now", used for recency decay.
    ///   - limit: Maximum suggestions to return (default 15).
    static func suggestions(
        fitPics: [FitPic],
        excluding selected: [String],
        referenceDate: Date = Date(),
        limit: Int = 15,
        calendar: Calendar = .current
    ) -> [String] {
        let excluded = Set(selected)

        // 1. Rank the user's own tags by recency-weighted frequency.
        let ranked = rankedUserTags(
            fitPics: fitPics,
            referenceDate: referenceDate,
            calendar: calendar
        ).filter { !excluded.contains($0) }

        var result = Array(ranked.prefix(limit))

        // 2. Fill remaining slots from the seed list (skip anything already present/excluded).
        if result.count < limit {
            let taken = excluded.union(result)
            for seed in seedTags where !taken.contains(seed) {
                result.append(seed)
                if result.count == limit { break }
            }
        }

        return result
    }

    // MARK: - Ranking

    /// The user's distinct tags ordered by descending recency-weighted-frequency score.
    /// Ties break alphabetically for stable ordering.
    static func rankedUserTags(
        fitPics: [FitPic],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        var scores: [String: Double] = [:]

        for pic in fitPics {
            let weight = recencyWeight(for: pic.date, referenceDate: referenceDate, calendar: calendar)
            for tag in pic.tags {
                scores[tag, default: 0] += weight
            }
        }

        return scores
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map(\.key)
    }

    /// Recency decay weight in [0, 1]: 1.0 today, 0.5 one half-life ago, etc.
    private static func recencyWeight(
        for date: Date, referenceDate: Date, calendar: Calendar
    ) -> Double {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: referenceDate)
        let ageDays = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        // Future-dated safety: clamp negative ages to 0.
        let age = Double(max(ageDays, 0))
        return pow(0.5, age / halfLifeDays)
    }
}

// MARK: - Store convenience

extension FitPicStore {
    /// Suggested tags for composing a post, excluding those already selected.
    func tagSuggestions(excluding selected: [String], limit: Int = 15) -> [String] {
        TagSuggestionEngine.suggestions(fitPics: fitPics, excluding: selected, limit: limit)
    }
}
