import Foundation
import Combine

// MARK: - FitPic

struct FitPic: Identifiable, Codable {
    let id: UUID
    let date: Date
    let imagePath: String
    var tags: [String]

    init(id: UUID = UUID(), date: Date = Date(), imagePath: String, tags: [String] = []) {
        self.id = id
        self.date = date
        self.imagePath = imagePath
        self.tags = tags
    }
}

// MARK: - FitPicStore

final class FitPicStore: ObservableObject {
    @Published private(set) var fitPics: [FitPic] = []

    private let saveKey = "fitPicsData"

    init() { load() }

    // MARK: Queries

    /// All fit pics, newest first (descending by capture time).
    var allSorted: [FitPic] {
        fitPics.sorted { $0.date > $1.date }
    }

    /// Fit pics grouped by calendar day, newest day first, and newest pic first within each day.
    /// Each element is the start-of-day `Date` paired with that day's pics.
    var groupedByDay: [(day: Date, pics: [FitPic])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: fitPics) { calendar.startOfDay(for: $0.date) }
        return groups
            .map { (day: $0.key, pics: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    /// All fit pics recorded on the given calendar day, newest first.
    func fitPicsForDate(_ date: Date) -> [FitPic] {
        fitPics
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }

    /// All fit pics carrying the given tag, newest first.
    func fitPicsWithTag(_ tag: String) -> [FitPic] {
        fitPics
            .filter { $0.tags.contains(tag) }
            .sorted { $0.date > $1.date }
    }

    // MARK: Mutations

    /// Appends a new FitPic without removing any existing ones for the same day.
    func add(_ fitPic: FitPic) {
        fitPics.append(fitPic)
        fitPics.sort { $0.date > $1.date }
        save()
    }

    func update(_ fitPic: FitPic) {
        guard let index = fitPics.firstIndex(where: { $0.id == fitPic.id }) else { return }
        fitPics[index] = fitPic
        save()
    }

    func delete(_ fitPic: FitPic) {
        fitPics.removeAll { $0.id == fitPic.id }
        save()
    }

    // MARK: Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(fitPics)
            UserDefaults.standard.set(data, forKey: saveKey)
        } catch {
            print("[FitPicStore] save error: \(error)")
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([FitPic].self, from: data)
            fitPics = decoded.sorted { $0.date > $1.date }
        } catch {
            print("[FitPicStore] load error: \(error)")
        }
    }
}
