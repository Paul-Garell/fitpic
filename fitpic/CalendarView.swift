import SwiftUI

// MARK: - CalendarView

struct CalendarView: View {
    @EnvironmentObject private var store: FitPicStore
    @State private var months: [Date] = []
    @State private var selectedDay: SelectedDay? = nil

    init() {
        let calendar = Calendar.current
        let startMonth = calendar.date(byAdding: .month, value: -6, to: Date())!
        var initial: [Date] = []
        for i in 0..<12 {
            if let month = calendar.date(byAdding: .month, value: i, to: startMonth) {
                initial.append(month)
            }
        }
        _months = State(initialValue: initial)
    }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(months, id: \.self) { month in
                            MonthView(month: month) { day in
                                selectedDay = SelectedDay(date: day)
                            }
                            .id(month)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    let current = Calendar.current.startOfMonth(for: Date())
                    proxy.scrollTo(current, anchor: .center)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(item: $selectedDay) { selection in
            DayDetailView(day: selection.date)
                .environmentObject(store)
        }
    }
}

/// Identifiable wrapper so a tapped day can drive `.sheet(item:)`.
private struct SelectedDay: Identifiable {
    let date: Date
    var id: Date { date }
}

// MARK: - MonthView

struct MonthView: View {
    @EnvironmentObject private var store: FitPicStore
    let month: Date
    var onSelectDay: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(month, format: .dateTime.year().month(.wide))
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(daysInMonth, id: \.self) { day in
                    DayButton(
                        day: day,
                        fitPic: store.fitPicsForDate(day).first,
                        onSelect: { onSelectDay(day) }
                    )
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .primary.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }

    private var daysInMonth: [Date] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let start = calendar.startOfMonth(for: month)
        return (0..<range.count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }
}

// MARK: - DayButton

struct DayButton: View {
    let day: Date
    /// The representative (newest) fit pic for this day, if any.
    let fitPic: FitPic?
    /// Invoked when a day that has at least one fit pic is tapped.
    var onSelect: (() -> Void)? = nil

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        Button {
            if fitPic != nil { onSelect?() }
        } label: {
            ZStack {
                if let fitPic {
                    DayThumbnail(fitPic: fitPic, isToday: isToday)
                } else {
                    emptyDay
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(fitPic == nil)
    }

    /// The plain number cell shown when there is no fit pic for the day.
    private var emptyDay: some View {
        Text(day, format: .dateTime.day())
            .font(.body)
            .frame(width: 44, height: 44)
            .background(
                Circle().fill(isToday ? Color.blue.opacity(0.2) : Color.clear)
            )
            .overlay(
                Circle().stroke(
                    isToday ? Color.blue : Color.gray.opacity(0.2),
                    lineWidth: 1
                )
            )
    }
}

// MARK: - DayThumbnail

/// A small round photo thumbnail for a calendar day with a fit pic.
/// The day number sits in a badge on the corner so the date stays legible.
private struct DayThumbnail: View {
    let fitPic: FitPic
    let isToday: Bool

    @State private var image: UIImage?

    private let diameter: CGFloat = 40

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailCircle
            dayBadge
        }
        .task(id: fitPic.id) {
            image = await loadThumbnail()
        }
    }

    private var thumbnailCircle: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Color(.systemFill))
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(
            Circle().stroke(
                isToday ? Color.blue : Color.gray.opacity(0.3),
                lineWidth: isToday ? 2 : 1
            )
        )
    }

    private var dayBadge: some View {
        Text(fitPic.date, format: .dateTime.day())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(3)
            .background(Circle().fill(Color.black.opacity(0.6)))
    }

    private func loadThumbnail() async -> UIImage? {
        let path = fitPic.imagePath
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: ImageStorage.shared.loadThumbnail(path: path, maxPixelSize: 80))
            }
        }
    }
}

#Preview {
    CalendarView()
        .environmentObject(FitPicStore())
}
