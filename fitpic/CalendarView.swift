import SwiftUI

struct CalendarView: View {
    @State private var currentMonth = Date()
    @State private var months: [Date] = []
    
    let monthsToLoad = 12 // Load 12 months at a time
    
    init() {
        // Initialize with current month
        let calendar = Calendar.current
        let startMonth = calendar.date(byAdding: .month, value: -6, to: Date())!
        var initialMonths: [Date] = []
        
        for i in 0..<12 {
            if let month = calendar.date(byAdding: .month, value: i, to: startMonth) {
                initialMonths.append(month)
            }
        }
        _months = State(initialValue: initialMonths)
    }
    
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(months, id: \.self) { month in
                            MonthView(month: month)
                                .id(month)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    // Scroll to current month on appear
                    let currentMonth = Calendar.current.startOfMonth(for: Date())
                    proxy.scrollTo(currentMonth, anchor: .center)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct MonthView: View {
    let month: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Month header
            Text(month, format: .dateTime.year().month(.wide))
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            // Days grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(getDaysInMonth(month), id: \.self) { day in
                    DayButton(day: day)
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
    
    private func getDaysInMonth(_ month: Date) -> [Date] {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: month)!
        let startOfMonth = calendar.startOfMonth(for: month)
        
        return (0..<range.count).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: startOfMonth)
        }
    }
}

struct DayButton: View {
    let day: Date
    
    var body: some View {
        Button(action: {
            print("Day clicked: \(day)")
        }) {
            Text(day, format: .dateTime.day())
                .font(.body)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isToday(day) ? Color.blue.opacity(0.2) : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(isToday(day) ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}

#Preview {
    CalendarView()
}