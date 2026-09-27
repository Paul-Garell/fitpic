import Foundation

// MARK: - FitPicStats

/// Pure, dependency-free statistics derived from a collection of fit pics.
/// Kept separate from the store and views so the math is easy to reason about and test.
struct FitPicStats {

    let totalPhotos: Int
    let daysTracked: Int
    let currentStreak: Int
    let longestStreak: Int
    let averagePerActiveDay: Double
    let firstDate: Date?
    let mostRecentDate: Date?
    /// Tag → usage count, sorted by count descending then alphabetically.
    let topTags: [(tag: String, count: Int)]

    /// Builds stats from the given fit pics, evaluated relative to `referenceDate` (today).
    init(fitPics: [FitPic], referenceDate: Date = Date(), calendar: Calendar = .current) {
        totalPhotos = fitPics.count

        // Distinct calendar days that have at least one pic.
        let dayStarts = Set(fitPics.map { calendar.startOfDay(for: $0.date) })
        daysTracked = dayStarts.count

        averagePerActiveDay = daysTracked == 0
            ? 0
            : Double(totalPhotos) / Double(daysTracked)

        let dates = fitPics.map(\.date)
        firstDate = dates.min()
        mostRecentDate = dates.max()

        let sortedDays = dayStarts.sorted()
        currentStreak = Self.currentStreak(
            days: dayStarts, referenceDate: referenceDate, calendar: calendar
        )
        longestStreak = Self.longestStreak(sortedDays: sortedDays, calendar: calendar)

        topTags = Self.topTags(fitPics: fitPics)
    }

    // MARK: Streaks

    /// Consecutive days with a pic ending today (or yesterday, so a day isn't
    /// "broken" until fully missed). Returns 0 if neither today nor yesterday has one.
    private static func currentStreak(
        days: Set<Date>, referenceDate: Date, calendar: Calendar
    ) -> Int {
        let today = calendar.startOfDay(for: referenceDate)

        // Anchor the streak at today if present, else yesterday, else no streak.
        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Longest run of consecutive days anywhere in the history.
    private static func longestStreak(sortedDays: [Date], calendar: Calendar) -> Int {
        guard !sortedDays.isEmpty else { return 0 }

        var longest = 1
        var run = 1
        for i in 1..<sortedDays.count {
            let previous = sortedDays[i - 1]
            let current = sortedDays[i]
            if let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: current) {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }
        return longest
    }

    // MARK: Tags

    private static func topTags(fitPics: [FitPic], limit: Int = 5) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for pic in fitPics {
            for tag in pic.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(limit)
            .map { (tag: $0.key, count: $0.value) }
    }
}

// MARK: - Store convenience

extension FitPicStore {
    /// Statistics computed from the current fit pics.
    var stats: FitPicStats {
        FitPicStats(fitPics: fitPics)
    }
}
