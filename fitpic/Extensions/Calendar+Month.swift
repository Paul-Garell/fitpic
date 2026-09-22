import Foundation

extension Calendar {
    /// Returns a Date representing the first moment of the month containing `date`.
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps)!
    }
}
